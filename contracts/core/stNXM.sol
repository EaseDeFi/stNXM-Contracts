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

    // Initialize here
    function initialize(address _dex) external initializer {
        dex = _dex;
    }

    modifier notPaused {
        require(!paused, "Contract is currently paused.");
        _;
    }

/******************************************************************************************************************************************/
/**************************************************************** Public ****************************************************************/
/******************************************************************************************************************************************

    /**
     * @dev Withdraw an amount of wNxm or NXM by burning arNxm.
     * @param _stAmount The amount of arNxm to burn for the wNxm withdraw.
     *
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
     * @dev Finalize withdraw request after withdrawal delay
     * We need to adjust this so that it checks nAmount on withdraw request, then it checks again here, and the lower price is used.
     * This is so that people both cannot get a fixed price for withdrawal (without slashing) right before we pause the contract,
     * and so people cannot have an open request that continues gaining yield but that can be finalized at any time.
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
     * @dev collect rewards from staking pool
     * We probably want to upgrade this so that we store tranches for each
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

    function resetTranches()
      public
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256[] memory tranches;
            // Find tranches here and add to tokenIds
        }
    }

    /**
     * @dev Collect fees from the Uni V3 pool
     *
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
     * @dev Used to withdraw nxm from staking pool after tranche expires
     * @param _tokenId Staking NFT token id
     * @param _trancheIds tranches to unstake from
     *
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
     * @dev Used to stake nxm tokens to stake pool. it is determined manually
     *
     */
    function stakeNxm(uint256 _amount, address _poolAddress, uint256 _trancheId, uint256 _requestTokenId)
        external
        onlyOwner
    {
        _stakeNxm(_amount, _poolAddress, _trancheId, _requestTokenId);
    }

    /**
     * @dev Extend deposit in staking pool
     * @param _tokenId Staking NFT token id
     * @param _initialTrancheId initial tranche id
     * @param _newTrancheId new tranche id
     * @param _topUpAmount top up amount
     *
     */
    function extendDeposit(uint256 _tokenId, uint256 _initialTrancheId, uint256 _newTrancheId, uint256 _topUpAmount)
        external
        onlyOwner
    {
        IStakingPool(tokenIdToPool[_tokenId]).extendDeposit(_tokenId, _initialTrancheId, _newTrancheId, _topUpAmount);
    }

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

    // deposit to morpho
    // this also needs to be kept track of in assets
    function morphoDeposit(uint256 _assetAmount) external onlyOwner {
        morpho.deposit(_assetAmount, address(this));
    }

    // withdraw from morpho
    function morphoRedeem(uint256 _shareAmount) external onlyOwner {
        morpho.redeem(_shareAmount, address(this));
    }

/******************************************************************************************************************************************/
/**************************************************************** View ****************************************************************/
/******************************************************************************************************************************************/

    function totalAssets() public view override returns (uint256) {
        // Add staked NXM, NXM in the contract, NXM in the dex and Morpho, subtract the recent chunk of reward from Nexus (because it's wrongfully included in balance),
        // add back in the amount that has been distributed so far, subtract the total amount that's waiting to be withdrawn.
        return _stakedNxm() + _unstakedNxm() - undistributedReward + distributedReward() - _totalPending();
    }

    function totalSupply() public view override returns (uint256) {
        // Do not include the "virtual" assets in the Uniswap pool in total supply calculations.
        return super.totalSupply() - dex.balance[1];
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

        for (uint256 i = 0; i < dexTokenIds.length; i++) assets += dex.getPosition(dexTokenIds[i]).amount0;
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

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

contract stOracle {

    // This is equivalent to 50% per year.
    // Way more than APY will ever be, but less
    // than needed for a useful price manipulation.
    uint256 constant saneApy = 5 * 1e17;
    uint256 public constant startTime;

    constructor() {
        startTime = block.timestamp;
    }

    // Find the price of stNXM in wNXM
    // Protections:
    // stNxm price on the dex will be very difficult to be too high because
    // minting is always available.
    function price() external view returns (uint256 price) {
        uint256 price = v3.getPrice(1e18);
        // Check if it's over a 
        require(sanePrice(price));

        // Scale to meet Morpho standards
        price = price * 1e36;
    }

    // Checks if the price isn't too high.
    // Since the only reason price should increase is because of profits from staking,
    // over 20% APY or so per year is an unreasonable gain and something is likely wrong.
    function sanePrice(uint256 _price) public view returns (bool) {
        // Amount of 1 year it's been
        uint256 elapsedTime = block.timestamp - startTime;
        // If price is lower than equal it's not too high.
        if (_price < 1e18) return true;
        uint256 apy = (_price - 1e18) * 31_536_000 / elapsedTime;
        return apy <= saneApy;
    }

}