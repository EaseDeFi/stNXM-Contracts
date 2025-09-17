/*

    Have a general arNXM staking setup. But include:
    1. Full pause when a hack occurs to stop withdrawals but allow deposits
    2. Ability to deposit to Uni V3, collect fees, add virtual stNXM, and have AUM exclude pool
    3. Required 2 day pause on withdrawal

*/
import '@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol';
import 'INonFungiblePositionManager.sol';
import 'IMorpho.sol';


contract stNXM is ERC4626, ERC721TokenReceiver {

   struct WithdrawalRequest {
        uint48 requestTime;
        uint104 nAmount;
        uint104 arAmount;
    }

    event Deposit(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event WithdrawRequested(address indexed user, uint256 share, uint256 asset, uint256 requestTime, uint256 withdrawTime);
    event Withdrawal(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event NxmReward(uint256 reward, uint256 timestamp, uint256 totalAum);

    uint256 private constant DENOMINATOR = 1000;

    // Nxm tokens.
    IERC20 public wNxm;
    IERC20 public nxm;
    // Nxm Master address.
    INxmMaster public nxmMaster;
    /// @dev Nexus mutual staking NFT
    IStakingNFT public stakingNFT;
    address public morphoToken;
    INonFungiblePositionManager public dex;

    uint256 public lastRewardTimestamp;
    // Delay to withdraw
    uint256 public withdrawDelay;
    // Total saved amount of withdrawals pending.
    uint256 public savedPending;
    // Amount of time that rewards are distributed over.
    uint256 public rewardDuration;
    // Withdrawals may be paused if a hack has recently happened. Timestamp of when the pause happened.
    uint256 public paused;
    // Amount of time withdrawals may be paused after a hack.
    uint256 public pauseDuration;
    // Address that will receive administration funds from the contract.
    address public beneficiary;
    // Percent of funds to be distributed for administration of the contract. 10 == 1%; 1000 == 100%.
    uint256 public adminPercent;
    // The amount of the last reward.
    uint256 public lastReward;

    // Ids for Uniswap NFTs
    uint256[] public dexTokenIds;

    /// @dev record of vaults NFT tokenIds
    uint256[] public tokenIds;
    /// @dev tokenId to risk pool address
    mapping(uint256 => address) public tokenIdToPool;
    mapping(uint256 => uint256[]) public tokenIdToTranches;


    mapping(address => WithdrawalRequest) public withdrawals;

/******************************************************************************************************************************************/
/**************************************************************** Main ****************************************************************/
/******************************************************************************************************************************************/

    function initialize(address _dex, address _wNxm, address _nxm, address _nxmMaster)
        public
    {
        Ownable.initializeOwnable();
        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        nxmMaster = INxmMaster(_nxmMaster);
        dex = _dex;
        adminPercent = 100;
        beneficiary = msg.sender;
        // restakePeriod = 3 days;
        rewardDuration = 7 days;
    }

    modifier notPaused {
        require(!paused, "Contract is currently paused.");
        _;
    }

/******************************************************************************************************************************************/
/**************************************************************** Public ****************************************************************/
/******************************************************************************************************************************************

    /**
     * @dev Underlying withdraw functions differently from ERC4626 because of the required delay.
     * @param caller The caller of the function to withdraw.
     * @param receiver The address to receive tokens from the withdraw.
     * @param owner The owner of the tokens to withdraw.
     * @param assets The amount of wNXM being withdrawn.
     * @param shares The amount of stNXM being withdrawn.
     */
    function _withdraw(        
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares) 
      internal 
      override
      notPaused
    {
        // This amount must be determined before arNxm burn.
        uint256 nAmount = convertToAssets(shares);

        require((totalPending() + nAmount) <= wNxm.balanceOf(address(this)), "Not enough NXM available for withdrawal.");

        savedPending = savedPending + nAmount;
        arNxm.safeTransferFrom(msg.sender, address(this), _stAmount);
        WithdrawalRequest memory prevWithdrawal = withdrawals[msg.sender];
        withdrawals[msg.sender] = WithdrawalRequest(
            uint48(block.timestamp),
            prevWithdrawal.nAmount + uint104(nAmount),
            prevWithdrawal.arAmount + uint104(_stAmount)
        );

        emit WithdrawRequested(msg.sender, _stAmount, nAmount, block.timestamp, block.timestamp + withdrawDelay);
    }

    /**
     * @notice Finalize a withdraw request after the withdraw delay ends.
     * @dev Only one withdraw request can be active at a time for a user so this needs no params.
     */
    function withdrawFinalize() external notPaused {
        address user = msg.sender;
        WithdrawalRequest memory withdrawal = withdrawals[user];

        uint256 currentAssetAmount = _convertToAssets(stAmount);
        uint256 nAmount = uint256(withdrawal.nAmount) > currentAssetAmount ? currentAssetAmount : uint256(withdrawal.nAmount);
        uint256 stAmount = uint256(withdrawal.stAmount);
        uint256 requestTime = uint256(withdrawal.requestTime);

        require((requestTime + withdrawDelay) <= block.timestamp, "Not ready to withdraw");
        require(nAmount > 0, "No pending amount to withdraw");

        _burn(address(this), stAmount);
        wNxm.safeTransfer(user, nAmount);
        delete withdrawals[user];
        savedPending = savedPending - nAmount;

        emit Withdrawal(user, nAmount, stAmount, block.timestamp);
    }

    /**
     * @notice Collect all rewards from Nexus staking pool and from dex.
     * @dev These rewards stream to users over the reward duration. Can be called by anyone once the duration is over.
     */
    function getRewardNxm() external  {
        // only allow to claim rewards after 1 week
        require((block.timestamp - lastRewardTimestamp) > rewardDuration, "reward interval not reached");
        uint256 prevAum = totalAssets();
        uint256 rewards;
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            rewards += _withdrawFromPool(tokenIdToPool[tokenId], tokenId, false, true, tokenIdsToTranches[tokenId]);
        }

        // Rewards to be given to users (full reward - admin reward).
        uint256 finalReward = _feeRewardsNxm(rewards);

        // Collect fees from the dex. Compounds back into stNXM value.
        collectDexFees();

        // update last reward
        undistributedReward = finalReward;
        if (finalReward > 0) emit NxmReward(rewards, block.timestamp, prevAum);
        lastRewardTimestamp = block.timestamp;
    }

    /**
     * @notice Check and reset all active tranches for each NFT ID. Can be called by anyone.
     */
    function resetTranches()
      public
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256[] memory futureTranches;
            address _stakingPool = tokenIdToPool[tokenIds[i]];

            for (uint256 j = 0; j < futureTranches.length; j++) {
                uint256 trancheDeposit = StakingPool(_stakingPool).getDeposit(tokenIds[i], futureTranches[j]);
                if (trancheDeposit > 0) tranches.push(futureTranches[j]);
            }
            
            tokenIdsToTranches[tokenIds[i]] = tranches;
        }
    }

    /**
     * @notice Collect fees from the Uni V3 pool
     */
    function collectDexFees(uint256 _tokenId)
        public
    {
        for (uint256 i = 0; i < dexNfts.length; i++) {
            INonfungiblePositionManager.Position memory position = dex.positions(dexTokenIds[i]);

            // amount0 is wNXM
            // amount1 is stNXM
            (uint256 amount0, uint256 amount1) = position.collect(
                address(this),          // recipient of the fees
                position.tickLower,      // lower tick of the position
                position.tickUpper       // upper tick of the position
            );

            // Burn the "virtual" stNXM
            if (amount1 > 0) _burn(address(this), amount1);
        }
    }

    /**
     * @notice Unstake NXM from pools once the allocation has expired. Can be called by anyone.
     * @param _tokenId Staking NFT token id.
     * @param _trancheIds Tranches to unstake from.
     */
    function unstakeNxm(uint256 _tokenId, uint256[] memory _trancheIds) external {
        uint256 withdrawn = _withdrawFromPool(tokenIdToPool[_tokenId], _tokenId, true, false, _trancheIds);
        nxm.approve(address(wNxm), _amount);
        IWNXM(address(wNxm)).wrap(_amount);
    }

/******************************************************************************************************************************************/
/**************************************************************** Owner Functionality ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @notice Owner can stake NXM to the desired pool and tranches. Privileged function.
     * @param _amount Amount of NXM to stake into the pool.
     * @param _poolAddress Address of the pool that we're staking to.
     * @param _trancheId ID of the tranche to stake to.
     * @param _requestTokenId Token ID we're adding to if it's already been minted.
     */
    function stakeNxm(uint256 _amount, address _poolAddress, uint256 _trancheId, uint256 _requestTokenId)
        external
        onlyOwner
    {
        _stakeNxm(_amount, _poolAddress, _trancheId, _requestTokenId);
    }

    /**
     * @notice Extend deposit in a pool we're currently staked in..
     * @param _tokenId Staking NFT token id.
     * @param _initialTrancheId Initial tranche id
     * @param _newTrancheId New tranche id.
     * @param _topUpAmount Top up amount (0 if we're not adding anything).
     *
     */
    function extendDeposit(uint256 _tokenId, uint256 _initialTrancheId, uint256 _newTrancheId, uint256 _topUpAmount)
        external
        onlyOwner
    {
        IStakingPool(tokenIdToPool[_tokenId]).extendDeposit(_tokenId, _initialTrancheId, _newTrancheId, _topUpAmount);
    }

    /**
     * @notice Used to mint a new Uni V3 position using funds from the stNXM pool.
     * @dev When minting, wNXM is added to the pool from here but stNXM is minted directly to the pool.
     *      Infinite amount of stNXM can be minted, only wNXM held by the contract can be added.
     * @param amount0ToAdd wNXM amount to add in the new position.
     * @param amount1ToAdd Amount of stNXM to mint to the Uni pool.
     * @param _tickLower Low tick of the new position.
     * @param _tickUpper High tick of the new position.
     */
    function mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd, uint128 _tickLower, uint128 _tickUpper)
        external
        onlyOwner
    {
        wNxm.approve(address(nonfungiblePositionManager), amount0ToAdd);
        _mint(address(this), amount1ToAdd);
        approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams memory params =
        INonfungiblePositionManager.MintParams({
            token0: address(wNxm),
            token1: address(this),
            fee: 3000,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: amount0ToAdd,
            amount1Desired: amount1ToAdd,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = dex.mint(params);

        dexTokenIds.push(tokenId);

        // Get rid of any stNXM tokens.
        if (amount1 < amount1ToAdd) {
            uint256 refund = amount1ToAdd - amount1;
            _burn(address(this), refund);
        }
    }

    /**
     * @notice Increase liquidity in a token that the vault already owns.
     * @param tokenId ID of the Uni NFT that we're adding to.
     * @param amount0ToAdd wNXM amount to add to the range.
     * @param amount1ToAdd stNXM amount to add to the range.
     */
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amount0ToAdd,
        uint256 amount1ToAdd
    ) external onlyOwner {
        wNxm.approve(address(nonfungiblePositionManager), amount0ToAdd);
        _mint(address(this), amount1ToAdd);
        approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amount0ToAdd,
            amount1Desired: amount1ToAdd,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (liquidity, amount0, amount1) = dex.increaseLiquidity(params);

        // Get rid of any stNXM tokens.
        if (amount1 < amount1ToAdd) {
            uint256 refund = amount1ToAdd - amount1;
            _burn(address(this), refund);
        }
    }

    /**
     * @notice Decrease liquidity in a token that the vault owns.
     * @param tokenId ID of the Uni NFT that we're removing from.
     * @param liquidity Amount of liquidity to remove from the token.
     */
    function decreaseLiquidityCurrentRange(uint256 tokenId, uint128 liquidity)
        external
        onlyOwner
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (amount0, amount1) = dex.decreaseLiquidity(params);

        // Burn stNXM that was removed.
        if (amount1 > 0) _burn(address(this), amount1);

        // If we're removing all liquidity, remove from tokenIds.
        if (dex.position(tokenId).amount0 == 0) {
            for (uint256 i = 0; i < dexTokenIds.length; i++) {
                if (tokenId == dexTokenIds[i]) {
                    dexTokenIds[i] = dexTokenIds[dexTokenIds.length - 1];
                    dexTokenIds.pop();
                }
            }
        }
    }

    /**
     * @notice Deposit wNXM to Morpho to be lent out with stNXM as collateral.
     * @param _assetAmount Amount of wNXM to be lent out.
     */
    function morphoDeposit(uint256 _assetAmount) external onlyOwner {
        morpho.deposit(_assetAmount, address(this));
    }

    /**
     * @notice Redeem Morpho assets to get wNXM back into the pool.
     * @param _shareAmount Amount of Morpho shares to redeem for wNXM.
     */
    function morphoRedeem(uint256 _shareAmount) external onlyOwner {
        morpho.redeem(_shareAmount, address(this));
    }

/******************************************************************************************************************************************/
/**************************************************************** View ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @notice Get total assets that the vault holds. 
     * @dev This is important to overwrite because it must include wNXM currently being held,
     *       NXM currently being staked, wNXM being lent out, wNXM being used as liquidity,
     *       and account for tokens currently being withdrawn and rewards being distributed.
     */
    function totalAssets() public view override returns (uint256) {
        // Add staked NXM, NXM in the contract, NXM in the dex and Morpho, subtract the recent chunk of reward from Nexus (because it's wrongfully included in balance),
        // add back in the amount that has been distributed so far, subtract the total amount that's waiting to be withdrawn.
        return _stakedNxm() + _unstakedNxm() - undistributedReward + distributedReward() - _totalPending();
    }

    /**
     * @notice Get the total supply of stNXM.
     * @dev The stNXM in the dex is "virtual" so it must be removed from total supply.
     */
    function totalSupply() public view override returns (uint256) {
        // Do not include the "virtual" assets in the Uniswap pool in total supply calculations.
        return super.totalSupply() - dex.balance1();
    }

    function _stakedNxm() internal view returns (uint256 assets) {
        uint256 stakedDeposit;
        INFTDescriptor nftDescriptor = INFTDescriptor(stakingNFT.nftDescriptor());

        for (uint256 i; i < tokenIds.length; i++) {
            (, uint256 totalStaked,) = nftDescriptor.getActiveDeposits(tokenIds[i], tokenIdToPool[tokenIds[i]]);
            assets += totalStaked;
        }
    }

    // Get the amount of NXM that's owned by this contract but is held elsewhere (specifically on a dex or lending protocol).
    function _unstakedNxm() internal view returns (uint256 assets) {
        assets = wNxm.balanceOf(address(this));

        morphoShares = morpho.balanceOf(address(this));
        assets += morpho.convertToAssets(morphoShares);

        for (uint256 i = 0; i < dexTokenIds.length; i++) assets += dex.positions(dexTokenIds[i]).amount0;
    }

    // Find the amount of wNXM that is pending to be withdrawn.
    // We pessimistically return the pending amount based on either saved at time of withdraw request or value today.
    function _totalPending() internal view returns (uint256) {
        uint256 currentPending = _convertToAssets(balanceOf(address(this)), Math.Rounding.Floor);
        return savedPending < currentPending ? savedPending : currentPending;
    }

    /**
     * @dev Calculate what the current reward is. We stream this to arNxm value to avoid dumps.
     * @return reward Amount of reward currently calculated into arNxm value.
     *
     */
    function _distributedReward() internal view returns (uint256 reward) {
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

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 ownerMax = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        uint256 nBalance = wNxm.balanceOf(address(this));
        return nBalance > ownerMax ? ownerMax : nBalance;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view virtual returns (uint256) {
        uint256 nBalance = _convertToShares(wNxm.balanceOf(address(this)));
        uint256 ownerBalance = balanceOf(owner);
        return nBalance > ownerBalance ? ownerBalance : nBalance;
    }

/******************************************************************************************************************************************/
/**************************************************************** Internal ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @dev Stake any wNxm over the amount we need to keep in reserve (bufferPercent% more than withdrawals last week).
     * @param _amount amount of NXM to stake
     * @param _poolAddress risk pool address
     * @param _trancheId tranche to stake NXM in
     * @param _requestTokenId token id of NFT
     *
     */
    function _stakeNxm(uint256 _amount, address _poolAddress, uint256 _trancheId, uint256 _requestTokenId) internal {
        IWNXM(address(wNxm)).unwrap(_amount);
        // Make sure it's the most recent token controller address.
        nxm.approve(nxmMaster.getLatestAddress("TC"), _amount);

        IStakingPool pool = IStakingPool(_poolAddress);
        uint256 tokenId = pool.depositTo(_amount, _trancheId, _requestTokenId, address(this));
        tokenIdsToTranches[tokenId].push(_trancheId);
        // if new nft token is minted we need to keep track of
        // tokenId and poolAddress inorder to calculate assets
        // under management
        if (tokenIdToPool[tokenId] == address(0)) {
            tokenIds.push(tokenId);
            tokenIdToPool[tokenId] = _poolAddress;
        }
    }

    /**
     * @dev Withdraw any Nxm we can from the staking pool.
     * @return amount The amount of funds that are being withdrawn.
     *
     */
    function _withdrawFromPool(
        address _poolAddress,
        uint256 _tokenId,
        bool _withdrawStake,
        bool _withdrawRewards,
        uint256[] memory _trancheIds
    ) internal returns (uint256 amount) {
        IStakingPool pool = IStakingPool(_poolAddress);
        (amount,) = pool.withdraw(_tokenId, _withdrawStake, _withdrawRewards, _trancheIds);
    }

    /**
     * @dev Find and distribute administrator rewards.
     * @param reward Full reward given from this week.
     * @return userReward Reward amount given to users (full reward - admin reward).
     *
     */
    function _feeRewardsNxm(uint256 reward) internal returns (uint256 userReward) {
        // Find both rewards before minting any.
        uint256 adminReward = _convertToShares((reward * adminPercent) / DENOMINATOR);

        // Mint to beneficary then this address (to then transfer to rewardManager).
        if (adminReward > 0) _mint(beneficiary, adminReward);

        userReward = reward - adminReward;
    }

/******************************************************************************************************************************************/
/**************************************************************** Administrative ****************************************************************/
/******************************************************************************************************************************************/

    // Owner can pause to stop withdrawing from occurring.
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /**
     * @dev Owner may change the withdraw delay.
     * @param _withdrawDelay Withdraw delay.
     *
     */
    function changeWithdrawDelay(uint256 _withdrawDelay) external onlyOwner {
        withdrawDelay = _withdrawDelay;
    }

    /**
     * @dev Change the percent of rewards that are given for administration of the contract.
     * @param _adminPercent The percent of rewards to be given for administration (10 == 1%, 1000 == 100%)
     *
     */
    function changeAdminPercent(uint256 _adminPercent) external onlyOwner {
        require(_adminPercent <= 500, "Cannot give admin more than 50% of rewards.");
        adminPercent = _adminPercent;
    }

    /**
     * @dev Owner may change the amount of time it takes to distribute rewards from Nexus.
     * @param _rewardDuration The amount of time it takes to fully distribute rewards.
     *
     */
    function changeRewardDuration(uint256 _rewardDuration) external onlyOwner {
        require(_rewardDuration <= 30 days, "Reward duration cannot be more than 30 days.");
        rewardDuration = _rewardDuration;
    }

    /**
     * @dev Change beneficiary of the administration funds.
     * @param _newBeneficiary Address of the new beneficiary to receive funds.
     *
     */
    function changeBeneficiary(address _newBeneficiary) external onlyOwner {
        beneficiary = _newBeneficiary;
    }

    /**
     * @dev remove token id from tokenIds array
     * @param _index Index of the tokenId to remove
     *
     */
    function removeTokenIdAtIndex(uint256 _index) external onlyOwner {
        uint256 tokenId = tokenIds[_index];
        tokenIds[_index] = tokenIds[tokenIds.length - 1];
        tokenIds.pop();
        // remove mapping to pool
        delete tokenIdToPool[tokenId];
    }

    /**
     * @dev rescue tokens locked in contract
     * @param token address of token to withdraw
     */
    function rescueToken(address token) external onlyOwner {
        require(token != address(wNxm), "Cannot rescue NXM");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

}