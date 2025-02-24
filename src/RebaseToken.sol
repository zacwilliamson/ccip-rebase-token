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

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author Zac Williamson
 * @dev Implements a rebase token with an ERC20 base and dynamic supply adjustments based on interest accrual.
 */
contract RebaseToken is ERC20 {
    // -----------------------------------------------------
    // Errors
    // -----------------------------------------------------
    error InterestRateCanOnlyDecrease(uint256 currentRate, uint256 attemptedRate);

    // -----------------------------------------------------
    // State Variables
    // -----------------------------------------------------
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10; // initial interest rate, can only be decreased
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_lastUpdatedTimestamp;

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
    constructor() ERC20("Rebase Token", "RBT") {}

    // -----------------------------------------------------
    // External Functions
    // -----------------------------------------------------

    /**
     * @notice Sets a new interest rate, which can only decrease to protect early users.
     * @param _newInterestRate The new interest rate to set.
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if (_newInterestRate >= s_interestRate) {
            revert InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mints tokens to a user based on the deposited amount and records their interest rate.
     * @param _to Address to mint tokens to.
     * @param _amount Amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
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

    // -----------------------------------------------------
    // Internal Functions
    // -----------------------------------------------------

    /**
     * @dev Updates the last updated timestamp for interest accrual calculation.
     * @param _user Address of the user to update.
     */
    function _mintAccruedInterest(address _user) internal {
        // find their current balance of rebase tokens that have been minted to the user (principle balance)
        // calculate their current balance including any interest -> balanceOf(_user)
        // calculate the number of tokens that need to be minted to the user
        // call _mint to mint the accruded interest to the user
        s_lastUpdatedTimestamp[_user] = block.timestamp;
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
}
