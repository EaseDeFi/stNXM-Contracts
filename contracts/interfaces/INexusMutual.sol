// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.17;

/**
 * @dev Quick interface for the Nexus Mutual contract to work with the Armor Contracts.
 **/

// to get nexus mutual contract address

// solhint-disable func-name-mixedcase

interface INxmMaster {
    function tokenAddress() external view returns (address);

    function owner() external view returns (address);

    function pauseTime() external view returns (uint);

    function masterInitialized() external view returns (bool);

    function isPause() external view returns (bool check);

    function isMember(address _add) external view returns (bool);

    function getLatestAddress(
        bytes2 _contractName
    ) external view returns (address payable contractAddress);

    function switchMembership(address _newMembership) external;
}

interface IPooledStaking {
    function unstakeRequests(
        uint256 id
    )
        external
        view
        returns (
            uint256 amount,
            uint256 unstakeAt,
            address contractAddress,
            address stakerAddress,
            uint256 next
        );

    function processPendingActions(
        uint256 iterations
    ) external returns (bool success);

    function lastUnstakeRequestId() external view returns (uint256);

    function stakerDeposit(address user) external view returns (uint256);

    function stakerMaxWithdrawable(
        address user
    ) external view returns (uint256);

    function withdrawReward(address user) external;

    function requestUnstake(
        address[] calldata protocols,
        uint256[] calldata amounts,
        uint256 insertAfter
    ) external;

    function depositAndStake(
        uint256 deposit,
        address[] calldata protocols,
        uint256[] calldata amounts
    ) external;

    function stakerContractCount(
        address staker
    ) external view returns (uint256);

    function stakerContractAtIndex(
        address staker,
        uint contractIndex
    ) external view returns (address);

    function stakerContractStake(
        address staker,
        address protocol
    ) external view returns (uint256);

    function stakerContractsArray(
        address staker
    ) external view returns (address[] memory);

    function stakerContractPendingUnstakeTotal(
        address staker,
        address protocol
    ) external view returns (uint256);

    function withdraw(uint256 amount) external;

    function stakerReward(address staker) external view returns (uint256);
}

interface IClaimsData {
    function getClaimStatusNumber(
        uint256 claimId
    ) external view returns (uint256, uint256);

    function getClaimDateUpd(uint256 claimId) external view returns (uint256);
}

interface INXMPool {
    function buyNXM(uint minTokensOut) external payable;
}

interface IGovernance {
    function submitVote(uint256 _proposalId, uint256 _solution) external;
}

interface IQuotation {
    function getWithdrawableCoverNoteCoverIds(
        address owner
    ) external view returns (uint256[] memory, bytes32[] memory);
}

interface IStakingPool {
    function ALLOCATION_UNITS_PER_NXM() external view returns (uint256);

    function BUCKET_DURATION() external view returns (uint256);

    function BUCKET_TRANCHE_GROUP_SIZE() external view returns (uint256);

    function CAPACITY_REDUCTION_DENOMINATOR() external view returns (uint256);

    function COVER_TRANCHE_GROUP_SIZE() external view returns (uint256);

    function GLOBAL_CAPACITY_DENOMINATOR() external view returns (uint256);

    function MAX_ACTIVE_TRANCHES() external view returns (uint256);

    function NXM_PER_ALLOCATION_UNIT() external view returns (uint256);

    function ONE_NXM() external view returns (uint256);

    function POOL_FEE_DENOMINATOR() external view returns (uint256);

    function REWARDS_DENOMINATOR() external view returns (uint256);

    function REWARD_BONUS_PER_TRANCHE_DENOMINATOR()
        external
        view
        returns (uint256);

    function REWARD_BONUS_PER_TRANCHE_RATIO() external view returns (uint256);

    function TRANCHE_DURATION() external view returns (uint256);

    function WEIGHT_DENOMINATOR() external view returns (uint256);

    function implementation() external view returns (address);

    function beacon() external view returns (address);

    function calculateNewRewardShares(
        uint256 initialStakeShares,
        uint256 stakeSharesIncrease,
        uint256 initialTrancheId,
        uint256 newTrancheId,
        uint256 blockTimestamp
    ) external pure returns (uint256);

    function coverContract() external view returns (address);

    function coverTrancheAllocations(uint256) external view returns (uint256);

    function depositTo(
        uint256 amount,
        uint256 trancheId,
        uint256 requestTokenId,
        address destination
    ) external returns (uint256 tokenId);

    function deposits(
        uint256,
        uint256
    )
        external
        view
        returns (
            uint96 lastAccNxmPerRewardShare,
            uint96 pendingRewards,
            uint128 stakeShares,
            uint128 rewardsShares
        );

    function expiringCoverBuckets(
        uint256,
        uint256,
        uint256
    ) external view returns (uint256);

    function extendDeposit(
        uint256 tokenId,
        uint256 initialTrancheId,
        uint256 newTrancheId,
        uint256 topUpAmount
    ) external;

    function getAccNxmPerRewardsShare() external view returns (uint256);

    function getActiveAllocations(
        uint256 productId
    ) external view returns (uint256[] memory trancheAllocations);

    function getActiveStake() external view returns (uint256);

    function getActiveTrancheCapacities(
        uint256 productId,
        uint256 globalCapacityRatio,
        uint256 capacityReductionRatio
    )
        external
        view
        returns (uint256[] memory trancheCapacities, uint256 totalCapacity);

    function getDeposit(
        uint256 tokenId,
        uint256 trancheId
    )
        external
        view
        returns (
            uint256 lastAccNxmPerRewardShare,
            uint256 pendingRewards,
            uint256 stakeShares,
            uint256 rewardsShares
        );

    function getExpiredTranche(
        uint256 trancheId
    )
        external
        view
        returns (
            uint256 accNxmPerRewardShareAtExpiry,
            uint256 stakeAmountAtExpiry,
            uint256 stakeSharesSupplyAtExpiry
        );

    function getFirstActiveBucketId() external view returns (uint256);

    function getFirstActiveTrancheId() external view returns (uint256);

    function getLastAccNxmUpdate() external view returns (uint256);

    function getMaxPoolFee() external view returns (uint256);

    function getNextAllocationId() external view returns (uint256);

    function getPoolFee() external view returns (uint256);

    function getPoolId() external view returns (uint256);

    function getRewardPerSecond() external view returns (uint256);

    function getRewardsSharesSupply() external view returns (uint256);

    function getStakeSharesSupply() external view returns (uint256);

    function getTranche(
        uint256 trancheId
    ) external view returns (uint256 stakeShares, uint256 rewardsShares);

    function getTrancheCapacities(
        uint256 productId,
        uint256 firstTrancheId,
        uint256 trancheCount,
        uint256 capacityRatio,
        uint256 reductionRatio
    ) external view returns (uint256[] memory trancheCapacities);

    function initialize(
        bool _isPrivatePool,
        uint256 _initialPoolFee,
        uint256 _maxPoolFee,
        uint256 _poolId,
        string memory ipfsDescriptionHash
    ) external;

    function isHalted() external view returns (bool);

    function isPrivatePool() external view returns (bool);

    function manager() external view returns (address);

    function masterContract() external view returns (address);

    function multicall(
        bytes[] memory data
    ) external returns (bytes[] memory results);

    function nxm() external view returns (address);

    function processExpirations(bool updateUntilCurrentTimestamp) external;

    function rewardPerSecondCut(uint256) external view returns (uint256);

    function setPoolDescription(string memory ipfsDescriptionHash) external;

    function setPoolFee(uint256 newFee) external;

    function setPoolPrivacy(bool _isPrivatePool) external;

    function stakingNFT() external view returns (address);

    function stakingProducts() external view returns (address);

    function tokenController() external view returns (address);

    function trancheAllocationGroups(
        uint256,
        uint256
    ) external view returns (uint256);

    function withdraw(
        uint256 tokenId,
        bool withdrawStake,
        bool withdrawRewards,
        uint256[] memory trancheIds
    ) external returns (uint256 withdrawnStake, uint256 withdrawnRewards);
}

// V2 Interfaces

interface IStakingNFT {
    function approve(address spender, uint256 id) external;

    function balanceOf(address owner) external view returns (uint256);

    function changeNFTDescriptor(address newNFTDescriptor) external;

    function changeOperator(address newOperator) external;

    function getApproved(uint256) external view returns (address);

    function isApprovedForAll(address, address) external view returns (bool);

    function isApprovedOrOwner(
        address spender,
        uint256 id
    ) external view returns (bool);

    function mint(uint256 poolId, address to) external returns (uint256 id);

    function name() external view returns (string memory);

    function nftDescriptor() external view returns (address);

    function operator() external view returns (address);

    function ownerOf(uint256 id) external view returns (address owner);

    function safeTransferFrom(address from, address to, uint256 id) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) external;

    function setApprovalForAll(address spender, bool approved) external;

    function stakingPoolFactory() external view returns (address);

    function stakingPoolOf(
        uint256 tokenId
    ) external view returns (uint256 poolId);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);

    function symbol() external view returns (string memory);

    function tokenInfo(
        uint256 tokenId
    ) external view returns (uint256 poolId, address owner);

    function tokenURI(uint256 id) external view returns (string memory uri);

    function totalSupply() external view returns (uint256);

    function transferFrom(address from, address to, uint256 id) external;
}

interface INFTDescriptor {
    struct StakeData {
        uint poolId;
        uint stakeAmount;
        uint tokenId;
    }

    function getActiveDeposits(
        uint256 tokenId,
        address stakingPool
    )
        external
        view
        returns (
            string memory depositInfo,
            uint256 totalStake,
            uint256 pendingRewards
        );
}
