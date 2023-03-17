// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.0;
// Library imports
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Local imports
import "../general/Ownable.sol";
import "../general/ERC721TokenReceiver.sol";

//  Interfaces
import "../interfaces/IERC20Mintable.sol";
import "../interfaces/IWNXM.sol";
import "../interfaces/INexusMutual.sol";
import "../interfaces/IRewardManager.sol";
import "../interfaces/IShieldMining.sol";

// solhint-disable not-rely-on-time
// solhint-disable reason-string
// solhint-disable max-states-count
// solhint-disable no-inline-assembly
// solhint-disable no-empty-blocks
// solhint-disable contract-name-camelcase
// solhint-disable var-name-mixedcase
// solhint-disable avoid-tx-origin

contract arNXMVault is Ownable, ERC721TokenReceiver {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Mintable;

    struct WithdrawalRequest {
        uint48 requestTime;
        uint104 nAmount;
        uint104 arAmount;
    }

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

    uint256 private constant DENOMINATOR = 1000;

    // Amount of time between
    uint256 private ____deprecated____0;

    // Amount of time that rewards are distributed over.
    uint256 public rewardDuration;

    // This used to be unstake percent but has now been deprecated in favor of individual unstakes.
    // Paranoia results in this not being replaced but rather deprecated and new variables placed at the bottom.
    uint256 private ____deprecated____1;

    // Amount of wNXM (in token Wei) to reserve each period.
    // Overwrites reservePercent in update.
    uint256 public reserveAmount;

    // Withdrawals may be paused if a hack has recently happened. Timestamp of when the pause happened.
    uint256 public withdrawalsPaused;

    // Amount of time withdrawals may be paused after a hack.
    uint256 public pauseDuration;

    // Address that will receive administration funds from the contract.
    address public beneficiary;

    // Percent of funds to be distributed for administration of the contract. 10 == 1%; 1000 == 100%.
    uint256 public adminPercent;

    // Percent of staking rewards that referrers get.
    uint256 public referPercent;

    // Timestamp of when the last restake took place--7 days between each.
    uint256 private ____deprecated____2;

    // The amount of the last reward.
    uint256 public lastReward;

    // Uniswap, Maker, Compound, Aave, Curve, Synthetix, Yearn, RenVM, Balancer, dForce.
    address[] public protocols;

    // Amount to unstake each time.
    uint256[] private ____deprecated____3;

    // Protocols being actively used in staking or unstaking.
    address[] private ____deprecated____4;

    // Nxm tokens.
    IERC20 public wNxm;
    IERC20 public nxm;
    IERC20Mintable public arNxm;

    // Nxm Master address.
    INxmMaster public nxmMaster;

    // Reward manager for referrers.
    IRewardManager public rewardManager;

    // Referral => referrer
    mapping(address => address) public referrers;

    /*//////////////////////////////////////////////////////////////
                            FIRST UPDATE
    //////////////////////////////////////////////////////////////*/

    uint256 public lastRewardTimestamp;

    /*//////////////////////////////////////////////////////////////
                            SECOND UPDATE
    //////////////////////////////////////////////////////////////*/

    // Protocol that the next restaking will begin on.
    uint256 private ____deprecated____5;

    // Checkpoint in case we want to cut off certain buckets (where we begin the rotations).
    // To bar protocols from being staked/unstaked, move them to before checkpointProtocol.
    uint256 private ____deprecated____6;

    // Number of protocols to stake each time.
    uint256 private ____deprecated____7;

    // Individual percent to unstake.
    uint256[] private ____deprecated____8;

    // Last time an EOA has called this contract.
    mapping(address => uint256) private ____deprecated____9;

    /*//////////////////////////////////////////////////////////////
                            THIRD UPDATE
    //////////////////////////////////////////////////////////////*/

    // Withdraw fee to withdraw immediately.
    uint256 public withdrawFee;

    // Delay to withdraw
    uint256 public withdrawDelay;

    // Total amount of withdrawals pending.
    uint256 public totalPending;

    mapping(address => WithdrawalRequest) public withdrawals;

    /*//////////////////////////////////////////////////////////////
                            FOURTH UPDATE
    //////////////////////////////////////////////////////////////*/

    /// @dev record of vaults NFT tokenIds
    uint256[] public tokenIds;

    /// @dev tokenId to risk pool address
    mapping(uint256 => address) public tokenIdToPool;

    /// @dev timestamp for last call to nexus pools get reward
    uint256 public lastRewardCollected;

    /// @dev Nexus mutual staking NFT
    IStakingNFT public stakingNFT;

    /*//////////////////////////////////////////////////////////////
                            MODIFIER'S
    //////////////////////////////////////////////////////////////*/
    ///@dev Avoid composability issues for liquidation.
    modifier notContract() {
        require(msg.sender == tx.origin, "Sender must be an EOA.");
        _;
    }

    /**
     * @param _wNxm Address of the wNxm contract.
     * @param _arNxm Address of the arNxm contract.
     * @param _nxmMaster Address of Nexus' master address (to fetch others).
     * @param _rewardManager Address of the ReferralRewards smart contract.
     **/
    function initialize(
        address _wNxm,
        address _arNxm,
        address _nxm,
        address _nxmMaster,
        address _rewardManager
    ) public {
        require(
            address(arNxm) == address(0),
            "Contract has already been initialized."
        );

        Ownable.initializeOwnable();
        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        arNxm = IERC20Mintable(_arNxm);
        nxmMaster = INxmMaster(_nxmMaster);
        rewardManager = IRewardManager(_rewardManager);
        // unstakePercent = 100;
        adminPercent = 0;
        referPercent = 25;
        reserveAmount = 30 ether;
        pauseDuration = 10 days;
        beneficiary = msg.sender;
        // restakePeriod = 3 days;
        rewardDuration = 9 days;

        // Approve to wrap and send funds to reward manager.
        arNxm.approve(_rewardManager, type(uint256).max);
    }

    /**
     * @dev Set's initial state for nexus mutual v2
     * @param _stakingNFT Nexus mutual staking NFT contract
     * @param _tokenIds Array of tokenIds this vault initially owns
     * @param _riskPools Array of risk pools this vault has initially staked into
     **/
    function initializeV2(
        IStakingNFT _stakingNFT,
        uint[] memory _tokenIds,
        address[] memory _riskPools
    ) external onlyOwner {
        require(address(stakingNFT) == address(0), "initialized already");
        require(_tokenIds.length == _riskPools.length, "length mismatch");

        tokenIds = _tokenIds;
        for (uint i; i < _tokenIds.length; i++) {
            tokenIdToPool[_tokenIds[i]] = _riskPools[i];
        }
        stakingNFT = _stakingNFT;

        _collectOldRewards();
    }

    /**
     * @dev Deposit wNxm or NXM to get arNxm in return.
     * @param _nAmount The amount of NXM to stake.
     * @param _referrer The address that referred this user.
     * @param _isNxm True if the token is NXM, false if the token is wNXM.
     **/
    function deposit(
        uint256 _nAmount,
        address _referrer,
        bool _isNxm
    ) external {
        if (referrers[msg.sender] == address(0)) {
            referrers[msg.sender] = _referrer != address(0)
                ? _referrer
                : beneficiary;
            address refToSet = _referrer != address(0)
                ? _referrer
                : beneficiary;
            referrers[msg.sender] = refToSet;

            // A wallet with a previous arNXM balance would be able to subtract referral weight that it never added.
            uint256 prevBal = arNxm.balanceOf(msg.sender);
            if (prevBal > 0) rewardManager.stake(refToSet, msg.sender, prevBal);
        }

        // This amount must be determined before arNxm mint.
        uint256 arAmount = arNxmValue(_nAmount);

        if (_isNxm) {
            nxm.safeTransferFrom(msg.sender, address(this), _nAmount);
        } else {
            wNxm.safeTransferFrom(msg.sender, address(this), _nAmount);
            _unwrapWnxm(_nAmount);
        }

        // Mint also increases sender's referral balance through alertTransfer.
        arNxm.mint(msg.sender, arAmount);

        emit Deposit(msg.sender, _nAmount, arAmount, block.timestamp);
    }

    /**
     * @dev Withdraw an amount of wNxm or NXM by burning arNxm.
     * @param _arAmount The amount of arNxm to burn for the wNxm withdraw.
     * @param _payFee Flag to pay fee to withdraw without delay.
     **/
    function withdraw(uint256 _arAmount, bool _payFee) external {
        require(
            (block.timestamp - withdrawalsPaused) > pauseDuration,
            "Withdrawals are temporarily paused."
        );

        // This amount must be determined before arNxm burn.
        uint256 nAmount = nxmValue(_arAmount);

        require(
            (totalPending + nAmount) <= nxm.balanceOf(address(this)),
            "Not enough NXM available for withdrawal."
        );

        if (_payFee) {
            uint256 fee = (nAmount * withdrawFee) / (1000);
            uint256 disbursement = (nAmount - fee);

            // Burn also decreases sender's referral balance through alertTransfer.
            arNxm.burn(msg.sender, _arAmount);
            _wrapNxm(disbursement);
            wNxm.safeTransfer(msg.sender, disbursement);

            emit Withdrawal(msg.sender, nAmount, _arAmount, block.timestamp);
        } else {
            totalPending = totalPending + nAmount;
            arNxm.safeTransferFrom(msg.sender, address(this), _arAmount);
            WithdrawalRequest memory prevWithdrawal = withdrawals[msg.sender];
            withdrawals[msg.sender] = WithdrawalRequest(
                uint48(block.timestamp),
                prevWithdrawal.nAmount + uint104(nAmount),
                prevWithdrawal.arAmount + uint104(_arAmount)
            );

            emit WithdrawRequested(
                msg.sender,
                _arAmount,
                nAmount,
                block.timestamp,
                block.timestamp + withdrawDelay
            );
        }
    }

    /**
     * @dev Finalize withdraw request after withdrawal delay
     **/
    function withdrawFinalize() external {
        address user = msg.sender;
        WithdrawalRequest memory withdrawal = withdrawals[user];
        uint256 nAmount = uint256(withdrawal.nAmount);
        uint256 arAmount = uint256(withdrawal.arAmount);
        uint256 requestTime = uint256(withdrawal.requestTime);

        require(
            (block.timestamp - withdrawalsPaused) > pauseDuration,
            "Withdrawals are temporarily paused."
        );
        require(
            (requestTime + withdrawDelay) <= block.timestamp,
            "Not ready to withdraw"
        );
        require(nAmount > 0, "No pending amount to withdraw");

        // Burn also decreases sender's referral balance through alertTransfer.
        arNxm.burn(address(this), arAmount);
        _wrapNxm(nAmount);
        wNxm.safeTransfer(user, nAmount);
        delete withdrawals[user];
        totalPending = totalPending - nAmount;

        emit Withdrawal(user, nAmount, arAmount, block.timestamp);
    }

    /**
     * @dev collect rewards from staking pool
     **/
    function getRewardNxm() external notContract {
        // only allow to claim rewards after 1 week
        require(
            (block.timestamp - lastRewardTimestamp) > rewardDuration,
            "reward interval not reached"
        );
        uint256 prevAum = aum();
        uint256 rewards;
        for (uint i; i < tokenIds.length; i++) {
            rewards += _getRewardsNxm(tokenIdToPool[tokenIds[i]], tokenIds[i]);
        }

        // update last reward
        lastReward = rewards;
        if (rewards > 0) {
            emit NxmReward(rewards, block.timestamp, prevAum);
        }
        lastRewardTimestamp = block.timestamp;
    }

    /**
     * @dev claim rewards from shield mining
     * @param _shieldMining shield mining contract address
     * @param _protocols Protocol funding the rewards.
     * @param _sponsors sponsor address who funded the shield mining
     * @param _tokens token address that sponsor is distributing
     **/
    function getShieldMiningRewards(
        address _shieldMining,
        address[] calldata _protocols,
        address[] calldata _sponsors,
        address[] calldata _tokens
    ) external notContract {
        IShieldMining(_shieldMining).claimRewards(
            _protocols,
            _sponsors,
            _tokens
        );
    }

    function aum() public view returns (uint256) {
        uint stakedDeposit;
        INFTDescriptor nftDescriptor = INFTDescriptor(
            stakingNFT.nftDescriptor()
        );

        for (uint i; i < tokenIds.length; i++) {
            (, uint totalStaked, ) = nftDescriptor.getActiveDeposits(
                tokenIds[i],
                tokenIdToPool[tokenIds[i]]
            );
            stakedDeposit += totalStaked;
        }
        // balance of this address

        return stakedDeposit + nxm.balanceOf(address(this));
    }

    /**
     * @dev Find the arNxm value of a certain amount of wNxm.
     * @param _nAmount The amount of NXM to check arNxm value of.
     * @return arAmount The amount of arNxm the input amount of wNxm is worth.
     **/
    function arNxmValue(
        uint256 _nAmount
    ) public view returns (uint256 arAmount) {
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();

        // aum() holds full reward so we sub lastReward (which needs to be distributed over time)
        // and add reward that has been distributed
        uint256 totalN = aum() + reward - lastReward;
        uint256 totalAr = arNxm.totalSupply();

        // Find exchange amount of one token, then find exchange amount for full value.
        if (totalN == 0) {
            arAmount = _nAmount;
        } else {
            uint256 oneAmount = (totalAr * 1e18) / totalN;
            arAmount = (_nAmount * oneAmount) / (1e18);
        }
    }

    /**
     * @dev Find the wNxm value of a certain amount of arNxm.
     * @param _arAmount The amount of arNxm to check wNxm value of.
     * @return nAmount The amount of wNxm the input amount of arNxm is worth.
     **/
    function nxmValue(uint256 _arAmount) public view returns (uint256 nAmount) {
        // Get reward allowed to be distributed.
        uint256 reward = _currentReward();

        // aum() holds full reward so we sub lastReward (which needs to be distributed over time)
        // and add reward that has been distributed
        uint256 totalN = aum() + reward - lastReward;
        uint256 totalAr = arNxm.totalSupply();

        // Find exchange amount of one token, then find exchange amount for full value.
        uint256 oneAmount = (totalN * 1e18) / totalAr;
        nAmount = (_arAmount * (oneAmount)) / 1e18;
    }

    /**
     * @dev Used to determine staked nxm amount in pooled staking contract.
     * @return staked Staked nxm amount.
     **/
    function stakedNxm() public view returns (uint256 staked) {
        staked = aum() - nxm.balanceOf(address(this));
    }

    /**
     * @dev Used to determine distributed reward amount
     * @return reward distributed reward amount
     **/
    function currentReward() external view returns (uint256 reward) {
        reward = _currentReward();
    }

    /**
     * @dev Anyone may call this function to pause withdrawals for a certain amount of time.
     *      We check Nexus contracts for a recent accepted claim, then can pause to avoid further withdrawals.
     * @param _claimId The ID of the cover that has been accepted for a confirmed hack.
     **/
    function pauseWithdrawals(uint256 _claimId) external {
        IClaimsData claimsData = IClaimsData(_getClaimsData());

        (, /*coverId*/ uint256 status) = claimsData.getClaimStatusNumber(
            _claimId
        );
        uint256 dateUpdate = claimsData.getClaimDateUpd(_claimId);

        // Status must be 14 and date update must be within the past 7 days.
        if (status == 14 && (block.timestamp - dateUpdate) <= 7 days) {
            withdrawalsPaused = block.timestamp;
        }
    }

    /**
     * @dev When arNXM tokens are transferred, the referrer stakes must be adjusted on RewardManager.
     *      This is taken care of by a "_beforeTokenTransfer" function on the arNXM ERC20.
     * @param _from The user that tokens are being transferred from.
     * @param _to The user that tokens are being transferred to.
     * @param _amount The amount of tokens that are being transferred.
     **/
    function alertTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) external {
        require(
            msg.sender == address(arNxm),
            "Sender must be the token contract."
        );

        // address(0) means the contract or EOA has not interacted directly with arNXM Vault.
        if (referrers[_from] != address(0))
            rewardManager.withdraw(referrers[_from], _from, _amount);
        if (referrers[_to] != address(0))
            rewardManager.stake(referrers[_to], _to, _amount);
    }

    /**
     * @dev Collect old rewards from nexus v1
     **/
    function _collectOldRewards() private {
        IPooledStaking pool = IPooledStaking(nxmMaster.getLatestAddress("PS"));
        // Find current reward, find user reward (transfers reward to admin within this).
        uint256 fullReward = pool.stakerReward(address(this));
        _feeRewardsNxm(fullReward);
        pool.withdrawReward(address(this));
    }

    /**
     * @dev Withdraw any available rewards from Nexus.
     * @return finalReward The amount of rewards to be given to users (full reward - admin reward - referral reward).
     **/
    function _getRewardsNxm(
        address _poolAddress,
        uint _tokenId
    ) internal returns (uint256 finalReward) {
        IStakingPool pool = IStakingPool(_poolAddress);

        // Find current reward, find user reward (transfers reward to admin within this).
        (, uint256 fullReward) = pool.withdraw(
            _tokenId,
            false,
            true,
            _getActiveTrancheIds()
        );
        finalReward = _feeRewardsNxm(fullReward);
    }

    /**
     * @dev Find and distribute administrator rewards.
     * @param reward Full reward given from this week.
     * @return userReward Reward amount given to users (full reward - admin reward).
     **/
    function _feeRewardsNxm(
        uint256 reward
    ) internal returns (uint256 userReward) {
        // Find both rewards before minting any.
        uint256 adminReward = arNxmValue((reward * adminPercent) / DENOMINATOR);
        uint256 referReward = arNxmValue((reward * referPercent) / DENOMINATOR);

        // Mint to beneficary then this address (to then transfer to rewardManager).
        if (adminReward > 0) {
            arNxm.mint(beneficiary, adminReward);
        }
        if (referReward > 0) {
            arNxm.mint(address(this), referReward);
            rewardManager.notifyRewardAmount(referReward);
        }

        userReward = reward - (adminReward + referReward);
    }

    /**
     * @dev Used to withdraw nxm from staking pool with ability to pass in risk pool address
     * @param _poolAddress risk pool address
     * @param _tokenId Staking NFT token id
     * @param _trancheIds tranches to unstake from
     **/
    function withdrawNxm(
        address _poolAddress,
        uint _tokenId,
        uint256[] memory _trancheIds
    ) external onlyOwner {
        _withdrawFromPool(_poolAddress, _tokenId, true, false, _trancheIds);
    }

    /**
     * @dev Used to unwrap wnxm tokens to nxm
     **/
    function unwrapWnxm() external {
        uint256 balance = wNxm.balanceOf(address(this));
        _unwrapWnxm(balance);
    }

    /**
     * @dev Used to stake nxm tokens to stake pool. it is determined manually
     **/
    function stakeNxm(
        uint _amount,
        address _poolAddress,
        uint _trancheId,
        uint _requestTokenId
    ) external onlyOwner {
        _stakeNxm(_amount, _poolAddress, _trancheId, _requestTokenId);
    }

    /**
     * @dev Used to withdraw nxm from staking pool after tranche expires
     * @param _tokenId Staking NFT token id
     * @param _trancheIds tranches to unstake from
     **/
    function unstakeNxm(
        uint _tokenId,
        uint256[] memory _trancheIds
    ) external onlyOwner {
        _withdrawFromPool(
            tokenIdToPool[_tokenId],
            _tokenId,
            true,
            false,
            _trancheIds
        );
    }

    /**
     * @dev Withdraw any Nxm we can from the staking pool.
     * @return amount The amount of funds that are being withdrawn.
     **/
    function _withdrawFromPool(
        address _poolAddress,
        uint _tokenId,
        bool _withdrawStake,
        bool _withdrawRewards,
        uint256[] memory _trancheIds
    ) internal returns (uint256 amount) {
        IStakingPool pool = IStakingPool(_poolAddress);
        (amount, ) = pool.withdraw(
            _tokenId,
            _withdrawStake,
            _withdrawRewards,
            _trancheIds
        );
    }

    /**
     * @dev Stake any wNxm over the amount we need to keep in reserve (bufferPercent% more than withdrawals last week).
     * @param _amount amount of NXM to stake
     * @param _poolAddress risk pool address
     * @param _trancheId tranche to stake NXM in
     * @param _requestTokenId token id of NFT
     **/
    function _stakeNxm(
        uint _amount,
        address _poolAddress,
        uint _trancheId,
        uint _requestTokenId
    ) internal {
        IStakingPool pool = IStakingPool(_poolAddress);
        uint256 balance = nxm.balanceOf(address(this));
        // If we do need to restake funds...
        // toStake == additional stake on top of old ones

        require(
            (reserveAmount + totalPending + _amount) <= balance,
            "Not enough NXM"
        );

        _approveNxm(_getTokenController(), _amount);
        uint tokenId = pool.depositTo(
            _amount,
            _trancheId,
            _requestTokenId,
            address(this)
        );
        // if new nft token is minted we need to keep track of
        // tokenId and poolAddress inorder to calculate assets
        // under management
        if (tokenIdToPool[tokenId] == address(0)) {
            tokenIds.push(tokenId);
            tokenIdToPool[tokenId] = _poolAddress;
        }
    }

    /**
     * @dev Calculate what the current reward is. We stream this to arNxm value to avoid dumps.
     * @return reward Amount of reward currently calculated into arNxm value.
     **/
    function _currentReward() internal view returns (uint256 reward) {
        uint256 duration = rewardDuration;
        uint256 timeElapsed = block.timestamp - lastRewardTimestamp;
        if (timeElapsed == 0) {
            return 0;
        }

        // Full reward is added to the balance if it's been more than the disbursement duration.
        if (timeElapsed >= duration) {
            reward = lastReward;
            // Otherwise, disburse amounts linearly over duration.
        } else {
            // 1e18 just for a buffer.
            uint256 portion = (duration * 1e18) / timeElapsed;
            reward = (lastReward * 1e18) / portion;
        }
    }

    /**
     * @dev Wrap Nxm tokens to be able to be withdrawn as wNxm.
     **/
    function _wrapNxm(uint256 _amount) internal {
        _approveNxm(address(wNxm), _amount);
        IWNXM(address(wNxm)).wrap(_amount);
    }

    /**
     * @dev Unwrap wNxm tokens to be able to be used within the Nexus Mutual system.
     * @param _amount Amount of wNxm tokens to be unwrapped.
     **/
    function _unwrapWnxm(uint256 _amount) internal {
        IWNXM(address(wNxm)).unwrap(_amount);
    }

    /**
     * @dev Approve wNxm contract to be able to transferFrom Nxm from this contract.
     **/
    function _approveNxm(address _to, uint256 _amount) internal {
        nxm.approve(_to, _amount);
    }

    /**
     * @dev Get the current NXM token controller (for NXM actions) from Nexus Mutual.
     * @return controller Address of the token controller.
     **/
    function _getTokenController() internal view returns (address controller) {
        controller = nxmMaster.getLatestAddress("TC");
    }

    /**
     * @dev Get current address of the Nexus Claims Data contract.
     * @return claimsData Address of the Nexus Claims Data contract.
     **/
    function _getClaimsData() internal view returns (address claimsData) {
        claimsData = nxmMaster.getLatestAddress("CD");
    }

    /// @dev get active trancheId's to collect rewards
    function _getActiveTrancheIds() internal view returns (uint256[] memory) {
        uint8 trancheCount = 9;
        uint trancheDuration = 91 days;
        uint256[] memory _trancheIds = new uint256[](trancheCount);

        // assuming we have not collected rewards from last expired tranche
        uint lastExpiredTrancheId = (block.timestamp / trancheDuration) - 1;
        for (uint256 i = 0; i < trancheCount; i++) {
            _trancheIds[i] = lastExpiredTrancheId + i;
        }
        return _trancheIds;
    }

    /*---- Ownable functions ----*/

    /**
     * @dev pull nxm from arNFT and wrap it to wnxm
     **/
    function pullNXM(
        address _from,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        nxm.transferFrom(_from, address(this), _amount);
        _wrapNxm(_amount);
        wNxm.transfer(_to, _amount);
    }

    /**
     * @dev Buy NXM direct from Nexus Mutual. Used by ExchangeManager.
     * @param _minNxm Minimum amount of NXM tokens to receive in return for the Ether.
     **/
    function buyNxmWithEther(uint256 _minNxm) external payable {
        require(
            msg.sender == 0x1337DEF157EfdeF167a81B3baB95385Ce5A14477,
            "Sender must be ExchangeManager."
        );
        INXMPool pool = INXMPool(nxmMaster.getLatestAddress("P1"));
        pool.buyNXM{value: address(this).balance}(_minNxm);
    }

    /**
     * @dev Vote on Nexus Mutual governance proposals using tokens.
     * @param _proposalId ID of the proposal to vote on.
     * @param _solutionChosen Side of the proposal we're voting for (0 for no, 1 for yes).
     **/
    function submitVote(
        uint256 _proposalId,
        uint256 _solutionChosen
    ) external onlyOwner {
        address gov = nxmMaster.getLatestAddress("GV");
        IGovernance(gov).submitVote(_proposalId, _solutionChosen);
    }

    /**
     * @dev rescue tokens locked in contract
     * @param token address of token to withdraw
     */
    function rescueToken(address token) external onlyOwner {
        require(
            token != address(nxm) &&
                token != address(wNxm) &&
                token != address(arNxm),
            "Cannot rescue NXM-based tokens"
        );
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

    function transferERC721Token(
        address to,
        address tokenAddress,
        uint tokenId
    ) external onlyOwner {
        // owner of this contract should not be able to transfer nxmStakingNFT
        // as stake nft can be traded being able to transfer it may cause centralization
        require(
            tokenAddress != address(stakingNFT),
            "cannot transfer stakingNFT"
        );

        IERC721(tokenAddress).transferFrom(address(this), to, tokenId);
    }

    /*---- Admin functions ----*/

    /**
     * @dev Owner may change how much of the AUM should be saved in reserve each period.
     * @param _reserveAmount The amount of wNXM (in token Wei) to reserve each period.
     **/
    function changeReserveAmount(uint256 _reserveAmount) external onlyOwner {
        reserveAmount = _reserveAmount;
    }

    /**
     * @dev Owner may change the percent of insurance fees referrers receive.
     * @param _referPercent The percent of fees referrers receive. 50 == 5%.
     **/
    function changeReferPercent(uint256 _referPercent) external onlyOwner {
        require(
            _referPercent <= 500,
            "Cannot give referrer more than 50% of rewards."
        );
        referPercent = _referPercent;
    }

    /**
     * @dev Owner may change the withdraw fee.
     * @param _withdrawFee The fee of withdraw.
     **/
    function changeWithdrawFee(uint256 _withdrawFee) external onlyOwner {
        require(
            _withdrawFee <= DENOMINATOR,
            "Cannot take more than 100% of withdraw"
        );
        withdrawFee = _withdrawFee;
    }

    /**
     * @dev Owner may change the withdraw delay.
     * @param _withdrawDelay Withdraw delay.
     **/
    function changeWithdrawDelay(uint256 _withdrawDelay) external onlyOwner {
        withdrawDelay = _withdrawDelay;
    }

    /**
     * @dev Change the percent of rewards that are given for administration of the contract.
     * @param _adminPercent The percent of rewards to be given for administration (10 == 1%, 1000 == 100%)
     **/
    function changeAdminPercent(uint256 _adminPercent) external onlyOwner {
        require(
            _adminPercent <= 500,
            "Cannot give admin more than 50% of rewards."
        );
        adminPercent = _adminPercent;
    }

    /**
     * @dev Owner may change the amount of time it takes to distribute rewards from Nexus.
     * @param _rewardDuration The amount of time it takes to fully distribute rewards.
     **/
    function changeRewardDuration(uint256 _rewardDuration) external onlyOwner {
        require(
            _rewardDuration <= 30 days,
            "Reward duration cannot be more than 30 days."
        );
        rewardDuration = _rewardDuration;
    }

    /**
     * @dev Owner may change the amount of time that withdrawals are paused after a hack is confirmed.
     * @param _pauseDuration The new amount of time that withdrawals will be paused.
     **/
    function changePauseDuration(uint256 _pauseDuration) external onlyOwner {
        require(
            _pauseDuration <= 30 days,
            "Pause duration cannot be more than 30 days."
        );
        pauseDuration = _pauseDuration;
    }

    /**
     * @dev Change beneficiary of the administration funds.
     * @param _newBeneficiary Address of the new beneficiary to receive funds.
     **/
    function changeBeneficiary(address _newBeneficiary) external onlyOwner {
        beneficiary = _newBeneficiary;
    }

    /**
     * @dev remove token id from tokenIds array
     * @param _index Index of the tokenId to remove
     **/
    function removeTokenIdAtIndex(uint _index) external onlyOwner {
        uint tokenId = tokenIds[_index];
        tokenIds[_index] = tokenIds[tokenIds.length - 1];
        tokenIds.pop();
        // remove mapping to pool
        delete tokenIdToPool[tokenId];
    }

    /**
     * @notice Needed for Nexus to prove this contract lost funds.
     * @param _coverAddress Address that we need to send 0 eth to to confirm we had a loss.
     */
    function proofOfLoss(address payable _coverAddress) external onlyOwner {
        _coverAddress.transfer(0);
    }
}
