// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass token addr to constructor
    // create deposit function that mints tokens to user
    // create redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault

    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    // 'indexed' allows us to sort the variable being emitted
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function deposit() external payable {
        // need to use amount of ETH the user has sent to mint tokens to user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. burn tokens
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. send the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}

// QUESTIONS:
// Why not import the RebaseToken contract and create a new instance of that in our contract instead?
