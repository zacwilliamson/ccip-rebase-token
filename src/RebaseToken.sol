// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Zac Williamson
 * @dev Implements a rebase token with an ERC20 base and dynamic supply adjustments based on interest accrual.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    // -----------------------------------------------------
    // Errors
    // -----------------------------------------------------
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentRate, uint256 attemptedRate);

    // -----------------------------------------------------
    // State Variables
    // -----------------------------------------------------
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = /* 5e10 */ (5 * PRECISION_FACTOR) / 1e8; // initial interest rate, can only be decreased
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_lastUpdatedTimestamp;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // -----------------------------------------------------
    // Events
    // -----------------------------------------------------
    event InterestRateSet(uint256 newInterestRate);

    // -----------------------------------------------------
    // Modifiers
    // -----------------------------------------------------

    // -----------------------------------------------------
    // Constructor
    // -----------------------------------------------------
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    // -----------------------------------------------------
    // External Functions
    // -----------------------------------------------------

    /**
     * @notice Sets a new interest rate, which can only decrease to protect early users.
     * @param _newInterestRate The new interest rate to set.
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mints tokens to a user based on the deposited amount and records their interest rate.
     * @param _to Address to mint tokens to.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns tokens when user withdraws from the vault
     * @param _from User to burn the tokens from
     * @param _amount Amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // common practice for mitigating dust
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function grantMintAndBurnRole(address account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, account);
    }

    // -----------------------------------------------------
    // Public Functions
    // -----------------------------------------------------

    /**
     * @notice Returns the user's balance adjusted for accrued interest.
     * @param _user The user whose balance to get.
     * @return balance The balance of the user including accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256 balance) {
        // get the current principle balance of the user (number of tokens minted)
        // multiply the principle balance by the interest accumulated in the time since the balance was last updated
        uint256 adjustedBalance =
            super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
        return adjustedBalance;
    }

    /*
    * @notice Transfer tokens from one user to another
    * @param _recipient The user to transfer the tokens to
    * @param _amount The amount of tokens to transfer
    * @return True if the transfer was successful
    */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /*
    * @notice Transfer tokens from one user to another
    * @param _sender The user to transfer the tokens from
    * @param _recipient The user to transfer the tokens to
    * @param _amount The amount of tokens to transfer
    * @return True if the transfer was successful
    */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }
    // -----------------------------------------------------
    // Internal Functions
    // -----------------------------------------------------

    /**
     * @dev Updates the last updated timestamp for interest accrual calculation.
     * Mint the accrued interest tot he user since the last time they interacted with the protocol (eg: burn, mint, transfer)
     * @param _user Address of the user to update.
     */
    function _mintAccruedInterest(address _user) internal {
        // find their current balance of rebase tokens that have been minted to the user (principle balance)
        uint256 previousBalance = super.balanceOf(_user);
        // calculate their current balance including any interest -> balanceOf(_user)
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user
        uint256 balanceIncrease = currentBalance - previousBalance;
        // call _mint to mint the accruded interest to the user
        s_lastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /**
     * @dev Calculates the interest accumulated since the last update for a user.
     * @param _user The user to calculate for.
     * @return linearInterest The amount of interest accumulated since last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_lastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    // -----------------------------------------------------
    // View & Pure Functions
    // -----------------------------------------------------

    /**
     * @notice Gets the current interest rate for a specific user.
     * @param _user The user whose interest rate to retrieve.
     * @return The interest rate of the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /*
     * @notice Get the principle balance of a user. This is the number of tokens that have actually been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol.
     * @param _user The user to get the principle balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /*
    * @notice Get the interest rate for the contract
    * @return The interest rate for the contract
    */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
