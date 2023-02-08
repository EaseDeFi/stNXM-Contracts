// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.17;

interface IShieldMining {
    function claimRewards(
        address[] calldata stakedContracts,
        address[] calldata sponsors,
        address[] calldata tokenAddresses
    ) external returns (uint[] memory tokensRewarded);
}
