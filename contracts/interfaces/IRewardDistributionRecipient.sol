// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IRewardDistributionRecipient {
    function notifyRewardAmount(uint256 reward) external payable;
}
