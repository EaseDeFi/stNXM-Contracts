
// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.0;

contract arNXMVaultEvents {

    event Deposit(
        address indexed user,
        uint256 nAmount,
        uint256 arAmount,
        uint256 timestamp
    );
    event WithdrawRequested(
        address indexed user,
        uint256 arAmount,
        uint256 nAmount,
        uint256 requestTime,
        uint256 withdrawTime
    );
    event Withdrawal(
        address indexed user,
        uint256 nAmount,
        uint256 arAmount,
        uint256 timestamp
    );

    event NxmReward(uint256 reward, uint256 timestamp, uint256 totalAum);
}