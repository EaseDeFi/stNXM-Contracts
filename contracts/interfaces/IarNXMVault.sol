// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;
import {IStakingNFT} from "./INexusMutual.sol";

interface IarNXMVault {
    function adminPercent() external view returns (uint256);

    function alertTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external;

    function arNxm() external view returns (address);

    function arNxmValue(
        uint256 _nAmount
    ) external view returns (uint256 arAmount);

    function aum() external view returns (uint256 aumTotal);

    function beneficiary() external view returns (address);

    function buyNxmWithEther(uint256 _minNxm) external;

    function changeAdminPercent(uint256 _adminPercent) external;

    function changeBeneficiary(address _newBeneficiary) external;

    function changePauseDuration(uint256 _pauseDuration) external;

    function changeReferPercent(uint256 _referPercent) external;

    function changeReserveAmount(uint256 _reserveAmount) external;

    function changeRewardDuration(uint256 _rewardDuration) external;

    function changeWithdrawDelay(uint256 _withdrawDelay) external;

    function changeWithdrawFee(uint256 _withdrawFee) external;

    function currentReward() external view returns (uint256 reward);

    function deposit(uint256 _nAmount, address _referrer, bool _isNxm) external;

    function getRewardNxm() external;

    function getShieldMiningRewards(
        address _shieldMining,
        address[] memory _protocols,
        address[] memory _sponsors,
        address[] memory _tokens
    ) external;

    function initialize(
        address _wNxm,
        address _arNxm,
        address _nxm,
        address _nxmMaster,
        address _rewardManager
    ) external;

    function isOwner() external view returns (bool);

    function lastCall(address) external view returns (uint256);

    function lastRestake() external view returns (uint256);

    function lastReward() external view returns (uint256);

    function lastRewardTimestamp() external view returns (uint256);

    function nxm() external view returns (address);

    function nxmMaster() external view returns (address);

    function nxmValue(
        uint256 _arAmount
    ) external view returns (uint256 nAmount);

    function owner() external view returns (address);

    function pauseDuration() external view returns (uint256);

    function pauseWithdrawals(uint256 _claimId) external;

    function protocols(uint256) external view returns (address);

    function pullNXM(address _from, uint256 _amount, address _to) external;

    function receiveOwnership() external;

    function receiveSecondOwnership() external;

    function referPercent() external view returns (uint256);

    function referrers(address) external view returns (address);

    function rescueToken(address token) external;

    function reserveAmount() external view returns (uint256);

    function rewardDuration() external view returns (uint256);

    function rewardManager() external view returns (address);

    function secondOwner() external view returns (address);

    function stakeNxm(
        address[] memory _protocols,
        uint256[] memory _stakeAmounts
    ) external;

    function stakedNxm() external view returns (uint256 staked);

    function submitVote(uint256 _proposalId, uint256 _solutionChosen) external;

    function totalPending() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function transferSecondOwnership(address newOwner) external;

    function unstakeNxm(
        uint256 _lastId,
        address[] memory _protocols,
        uint256[] memory _unstakeAmounts
    ) external;

    function unwrapWnxm() external;

    function wNxm() external view returns (address);

    function withdraw(uint256 _arAmount, bool _payFee) external;

    function withdrawDelay() external view returns (uint256);

    function withdrawFee() external view returns (uint256);

    function withdrawFinalize() external;

    function withdrawNxm() external;

    function withdrawals(
        address
    )
        external
        view
        returns (uint48 requestTime, uint104 nAmount, uint104 arAmount);

    function withdrawalsPaused() external view returns (uint256);

    // beacon proxy functions
    function implementation() external view returns (address impl);

    function proxyOwner() external view returns (address owner);

    function transferProxyOwnership(address _newOwner) external;

    function upgradeTo(address _implementation) external;

    // V2 Functions

    function initializeV2(
        IStakingNFT _stakingNFT,
        uint[] memory _tokenIds,
        address[] memory _riskPools
    ) external;

    function stakingNFT() external view returns (address);

    function tokenIds(uint index) external view returns (uint);

    function tokenIdToPool(uint tokenId) external view returns (address);

    function lastRewardCollected() external view returns (uint256);
}
