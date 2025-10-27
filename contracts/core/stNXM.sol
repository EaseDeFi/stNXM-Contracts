pragma solidity ^0.8.26;

import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol';
import '../libraries/v3-core/PositionValue.sol';

import "../general/Ownable.sol";
import "../general/ERC721TokenReceiver.sol";

import '../interfaces/INonfungiblePositionManager.sol';
import '../interfaces/IMorpho.sol';
import "../interfaces/IWNXM.sol";
import "../interfaces/INexusMutual.sol";
import "../interfaces/IUniswapFactory.sol";

import "forge-std/console2.sol";

contract StNXM is ERC4626Upgradeable, ERC721TokenReceiver, Ownable {
    using SafeERC20 for IERC20;

   struct WithdrawalRequest {
        uint48 requestTime;
        uint104 assets;
        uint104 shares;
    }

    event Deposit(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event WithdrawRequested(address indexed user, uint256 share, uint256 asset, uint256 requestTime, uint256 withdrawTime);
    event Withdrawal(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event NxmReward(uint256 reward, uint256 timestamp);

    uint256 private constant DIVISOR = 1000;

    // Nxm tokens.
    IERC20 public wNxm;
    IERC20 public nxm;
    // Nxm Master address.
    INxmMaster public nxmMaster;
    IMorpho public morpho;
    INonfungiblePositionManager public nfp;
    IUniswapV3Pool public dex;

    // Needed for morpho MarketParams
    address public morphoOracle;
    address public irm;
    Id public morphoId;
    // Delay to withdraw
    uint256 public withdrawDelay;
    // Total saved amount of withdrawals pending.
    uint256 public pending;
    // Withdrawals may be paused if a hack has recently happened. Timestamp of when the pause happened.
    bool public paused;
    // Address that will receive administration funds from the contract.
    address public beneficiary;
    // Percent of funds to be distributed for administration of the contract. 10 == 1%; 1000 == 100%.
    uint256 public adminPercent;
    // Amount of fees owed to the admin.
    uint256 public adminFees;
    // The amount of the last reward.
    uint256 public lastTotal;
    // The amount of stake on last update. Needed to make sure a balance change isn't an unstake.
    uint256 public lastStaked;
    uint256 public lastBalance;

    // Ids for Uniswap NFTs
    uint256[] public dexTokenIds;

    /// @dev record of vaults NFT tokenIds
    uint256[] public tokenIds;
    /// @dev tokenId to risk pool address
    mapping(uint256 => address) public tokenIdToPool;
    mapping(uint256 => uint256[]) public tokenIdToTranches;

    // All withdrawal requests
    mapping(address => WithdrawalRequest) public withdrawals;

/******************************************************************************************************************************************/
/**************************************************************** Main ****************************************************************/
/******************************************************************************************************************************************/

    function initialize(address _nfp, address _wNxm, address _nxm, address _nxmMaster, uint256 _mintAmount)
        public
        initializer
    {
        __ERC20_init("Staked NXM", "stNXM");
        __ERC4626_init(IERC20(_wNxm));
        Ownable.initializeOwnable();

        // Need to mint a certain amount and send it to owner. Maybe just arNXM total supply?
        _mint(owner(), _mintAmount);

        wNxm = IERC20(_wNxm);
        nxm = IERC20(_nxm);
        nxmMaster = INxmMaster(_nxmMaster);
        nfp = INonfungiblePositionManager(_nfp);
        adminPercent = 100;
        beneficiary = msg.sender;

        nxm.approve(address(wNxm), type(uint256).max);
    }

    function initializeTwo(address _dex, address _morpho, address _morphoOracle, uint256 _dexDeposit) external {
        require(msg.sender == owner(), "Only owner may call.");
        morpho = IMorpho(_morpho);
        dex = IUniswapV3Pool(_dex);

        // Clean this up, very gross.
        morphoOracle = _morphoOracle;
        irm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
        MarketParams memory marketParams = MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000);
        morphoId = Id.wrap(keccak256(abi.encode(marketParams)));

        _mintNewPosition(_dexDeposit, _dexDeposit, -887270, 887270);

        // Initialize with old token IDs
        tokenIds.push(214);
        tokenIdToPool[214] = 0x5A44002A5CE1c2501759387895A3b4818C3F50b3;
        tokenIds.push(215);
        tokenIdToPool[215] = 0x5A44002A5CE1c2501759387895A3b4818C3F50b3;
        tokenIds.push(242);
        tokenIdToPool[242] = 0x34D250E9fA70748C8af41470323B4Ea396f76c16;

        // Get the initial tranches
        uint256 firstTranche = block.timestamp / 91 days;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            address _stakingPool = tokenIdToPool[id];
            delete tokenIdToTranches[id];

            for (uint256 tranche = firstTranche; tranche < firstTranche + 8; tranche++) {
                (,,uint256 trancheDeposit,) = IStakingPool(_stakingPool).getDeposit(id, tranche);
                if (trancheDeposit > 0) {
                    tokenIdToTranches[id].push(tranche);
                    lastStaked += trancheDeposit;
                }
            }
        }

        lastBalance = wNxm.balanceOf(address(this));
    }

    // Update admin fees based on any changes that occurred between last deposit and withdrawal.
    // This is to be used on functions that have balance changes unrelated to rewards within them such as deposit/withdraw.
    modifier update {
        // Wrap NXM in case rewards were sent to the contract without us knowing
        uint256 nxmBalance = nxm.balanceOf(address(this));
        if (nxmBalance > 0) IWNXM(address(wNxm)).wrap(nxmBalance);

        uint256 balance = wNxm.balanceOf(address(this));
        uint256 staked = stakedNxm();

        // This only happens without another update if rewards have entered the contract.
        if (balance > lastBalance && lastStaked <= staked) adminFees += (balance - lastBalance) * adminPercent / DIVISOR;
        _;
        
        lastBalance = wNxm.balanceOf(address(this));
        lastStaked = stakedNxm();
    }

    modifier notPaused {
        require(!paused, "Contract is currently paused.");
        _;
    }

/******************************************************************************************************************************************/
/**************************************************************** Public ****************************************************************/
/******************************************************************************************************************************************

    // Change this so that caller pays, receiver receives, if there's a current withdrawal it fails

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
        address ,
        address ,
        uint256 assets,
        uint256 shares) 
      internal 
      override
      notPaused
      update
    {
        require(_convertToAssets(pending + shares, Math.Rounding.Floor) <= wNxm.balanceOf(address(this)), "Not enough NXM available for withdrawal.");

        pending += shares;
        _transfer(caller, address(this), shares);
        WithdrawalRequest memory prevWithdrawal = withdrawals[caller];
        withdrawals[caller] = WithdrawalRequest(
            uint48(block.timestamp),
            prevWithdrawal.assets + uint104(assets),
            prevWithdrawal.shares + uint104(shares)
        );

        emit WithdrawRequested(caller, shares, assets, block.timestamp, block.timestamp + withdrawDelay);
    }

    /// Need to override here so that we can add the update modifier.
    function _deposit(        
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares) 
      internal 
      override
      update
    {
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Finalize a withdraw request after the withdraw delay ends.
     * @dev Only one withdraw request can be active at a time for a user so this needs no params.
     */
    function withdrawFinalize(address _user) external notPaused update {
        //address user = msg.sender;
        WithdrawalRequest memory withdrawal = withdrawals[_user];

        uint256 shares = uint256(withdrawal.shares);
        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 requestTime = uint256(withdrawal.requestTime);

        require((requestTime + withdrawDelay) <= block.timestamp, "Not ready to withdraw");
        require(assets > 0, "No pending amount to withdraw");

        pending -= uint256(withdrawal.shares);
        delete withdrawals[_user];

        // We allow 1 day for the withdraw to be finalized, otherwise it's deleted.
        if (block.timestamp > requestTime + withdrawDelay + 1 days) {
            _transfer(address(this), _user, shares);
            return;
        }

        _burn(address(this), shares);
        wNxm.safeTransfer(_user, assets);
        emit Withdrawal(_user, assets, shares, block.timestamp);
    }

    /**
     * @notice Collect all rewards from Nexus staking pool and from dex.
     * @dev These rewards stream to users over the reward duration. Can be called by anyone once the duration is over.
     */
    function getRewards() external update returns (uint256 rewards) {
        console2.log("TRYING OUT GET REWARDS.");

        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            console2.logUint(tokenId);
            console2.logAddress(tokenIdToPool[tokenId]);
            console2.logUint(tokenIdToTranches[tokenId][0]);

            rewards += _withdrawFromPool(tokenIdToPool[tokenId], tokenId, false, true, tokenIdToTranches[tokenId]);
        }

        console2.logUint(rewards);

        // Collect fees from the dex. Compounds back into stNXM value.
        //rewards += collectDexFees();

        console2.logUint(rewards);

        // Update for any changes since last interaction
        // We don't run the modifier because changes within the function should add to admin fees.
        adminFees += rewards * adminPercent / DIVISOR;

        emit NxmReward(rewards, block.timestamp);
    }

    /**
     * @notice Collect fees from the Uni V3 pool
     * @dev Does not have update because it's called within getRewards.
     */
    function collectDexFees()
        public
        returns (uint256 rewards)
    {
        for (uint256 i = 0; i < dexTokenIds.length; i++) {
            // amount0 is wNXM
            // amount1 is stNXM
            (uint256 amount0, uint256 amount1) = nfp.collect(INonfungiblePositionManager.CollectParams(
                dexTokenIds[i],
                address(this),          // recipient of the fees
                0,                      // maximum amount of amount0
                0                       // maximum amount of amount1
            ));

            // Burn the stNXM fees.
            if (amount1 > 0) _burn(address(this), amount1);
            rewards += amount0;
        }
    }

    /**
     * @notice Unstake NXM from pools once the allocation has expired. Can be called by anyone.
     * @param _tokenId Staking NFT token id.
     * @param _trancheIds Tranches to unstake from.
     */
    function unstakeNxm(uint256 _tokenId, uint256[] memory _trancheIds) external update {
        uint256 withdrawn = _withdrawFromPool(tokenIdToPool[_tokenId], _tokenId, true, false, _trancheIds);
        IWNXM(address(wNxm)).wrap(withdrawn);
    }

    /**
     * @notice Check and reset all active tranches for each NFT ID. Can be called by anyone.
     */
    function resetTranches()
      public
      update
    {
        // Get the first active tranche
        uint256 firstTranche = block.timestamp / 91 days;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            address _stakingPool = tokenIdToPool[id];
            delete tokenIdToTranches[id];

            for (uint256 tranche = firstTranche; tranche < firstTranche + 8; tranche++) {
                (,,uint256 trancheDeposit,) = IStakingPool(_stakingPool).getDeposit(id, tranche);
                if (trancheDeposit > 0) tokenIdToTranches[id].push(tranche);
            }
        }
    }

    /**
     * @notice Withdraw all fees that have accrued to the admin.
     * @dev Callable by anyone.
     */
    function withdrawAdminFees() external update {
        wNxm.safeTransfer(beneficiary, adminFees);
        adminFees = 0;
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
        update
    {
        _stakeNxm(_amount, _poolAddress, _trancheId, _requestTokenId);
    }

    /**
     * @notice Extend deposit in a pool we're currently staked in.
     * @param _tokenId Staking NFT token id.
     * @param _initialTrancheId Initial tranche id
     * @param _newTrancheId New tranche id.
     * @param _topUpAmount Top up amount (0 if we're not adding anything).
     *
     */
    function extendDeposit(uint256 _tokenId, uint256 _initialTrancheId, uint256 _newTrancheId, uint256 _topUpAmount)
        external
        onlyOwner
        update
    {
        IStakingPool(tokenIdToPool[_tokenId]).extendDeposit(_tokenId, _initialTrancheId, _newTrancheId, _topUpAmount);
    }

    /**
     * @notice Deposit wNXM to Morpho to be lent out with stNXM as collateral.
     * @param _assetAmount Amount of wNXM to be lent out.
     */
    function morphoDeposit(uint256 _assetAmount) external onlyOwner update {
        wNxm.approve(address(morpho), _assetAmount);
        morpho.supply(MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000), _assetAmount, 0, address(this), "");
    }

    /**
     * @notice Redeem Morpho assets to get wNXM back into the pool.
     * @param _shareAmount Amount of Morpho shares to redeem for wNXM.
     */
    function morphoRedeem(uint256 _shareAmount) external onlyOwner update {
        morpho.withdraw(MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000), 0, _shareAmount, address(this), address(this));
    }

    /**
     * @notice Decrease liquidity in a token that the vault owns.
     * @param tokenId ID of the Uni NFT that we're removing from.
     * @param liquidity Amount of liquidity to remove from the token.
     */
    function decreaseLiquidity(uint256 tokenId, uint128 liquidity)
        external
        onlyOwner
        update
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (, uint256 amount1) = nfp.decreaseLiquidity(params);

        // Burn stNXM that was removed.
        if (amount1 > 0) _burn(address(this), amount1);

        // If we're removing all liquidity, remove from tokenIds.
        (,,,,,,,uint128 tokenLiq,,,,) = nfp.positions(tokenId);
        if (tokenLiq == 0) {
            for (uint256 i = 0; i < dexTokenIds.length; i++) {
                if (tokenId == dexTokenIds[i]) {
                    dexTokenIds[i] = dexTokenIds[dexTokenIds.length - 1];
                    dexTokenIds.pop();
                }
            }
        }
    }

/******************************************************************************************************************************************/
/**************************************************************** View ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @notice Get total assets that the vault holds. 
     * @dev This is important to overwrite because it must include wNXM currently being held,
     *       NXM currently being staked, wNXM being lent out, wNXM being used as liquidity,
     *       and account for tokens currently being withdrawn and rewards being distributed.
     *       This also does not always account for exact admin fees, so be wary of that.
     */
    function totalAssets() public view override returns (uint256) {
        // Add staked NXM, NXM in the contract, NXM in the dex and Morpho, subtract the recent chunk of reward from Nexus (because it's wrongfully included in balance),
        // add back in the amount that has been distributed so far, subtract the total amount that's waiting to be withdrawn.
        return stakedNxm() + unstakedNxm() - adminFees;
    }

    /**
     * @notice Get the total supply of stNXM.
     * @dev The stNXM in the dex is "virtual" so it must be removed from total supply.
     */
    function totalSupply() public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        // Do not include the "virtual" assets in the Uniswap pool in total supply calculations.
        (, uint256 virtualShares) = dexBalances();
        return super.totalSupply() - virtualShares;
    }

    /**
     * @notice Full amount of NXM that's been staked.
     */
    function stakedNxm() public view returns (uint256 assets) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 token = tokenIds[i];
            uint256[] memory trancheIds = tokenIdToTranches[token];
            address pool = tokenIdToPool[token];

            uint activeStake = IStakingPool(pool).getActiveStake();
            uint stakeSharesSupply = IStakingPool(pool).getStakeSharesSupply();

            // Used to determine if we need to check an expired tranche.
            uint256 currentTranche = block.timestamp / 91 days;
            for (uint256 j = 0; j < trancheIds.length; j++) {
                uint256 tranche = trancheIds[j];
                (, , uint256 stakeShares, ) = IStakingPool(pool).getDeposit(token, tranche);

                // Tranche has been expired so we need to do different calculations here.
                if (tranche < currentTranche) {
                    (, uint256 amountAtExpiry, uint256 sharesAtExpiry) = IStakingPool(pool).getExpiredTranche(tranche);
                    assets += (amountAtExpiry * stakeShares) / sharesAtExpiry;
                } else {
                    assets += (activeStake * stakeShares) / stakeSharesSupply;
                }
            }
        }
    }

    /**
     * @notice Get all NXM that isn't staked. This includes current balance, lent in Morpho, and liquidity on Uni.
     */
    function unstakedNxm() public view returns (uint256 assets) {
        assets = wNxm.balanceOf(address(this));
        assets += nxm.balanceOf(address(this));
        (uint256 amountAssets, ) = dexBalances();
        assets += amountAssets;
        assets += morphoBalance();
    }

    /**
     * @notice Find balances of both wNXM and stNXM within the Uniswap pool this contract uses.
     */
    function dexBalances() public view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatio,,,,,,) = dex.slot0();

        for (uint256 i = 0; i < dexTokenIds.length; i++) {
            (uint256 posAmount0, uint256 posAmount1) = PositionValue.total(nfp, dexTokenIds[i], sqrtRatio);
            amount0 += posAmount0;
            amount1 += posAmount1;
        }
    }

    function morphoBalance() public view returns (uint256 assets) {
        Position memory pos = morpho.position(morphoId, address(this));
        Market memory market = morpho.market(morphoId);
        // Convert shares to assets
        assets = (pos.supplyShares * uint256(market.totalSupplyAssets)) / uint256(market.totalSupplyShares);
    }

    /// stNXM includes the inability to withdraw if the amount is over what's in the contract balance.
    function maxWithdraw(address owner) public view override(ERC4626Upgradeable) returns (uint256) {
        uint256 ownerMax = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        uint256 assetBalance = wNxm.balanceOf(address(this));
        return assetBalance > ownerMax ? ownerMax : assetBalance;
    }

    /// stNXM includes the inability to redeem if the amount is over what's in the contract balance.
    function maxRedeem(address owner) public view override(ERC4626Upgradeable) returns (uint256) {
        uint256 assetBalance = _convertToShares(wNxm.balanceOf(address(this)), Math.Rounding.Floor);
        uint256 ownerBalance = balanceOf(owner);
        return assetBalance > ownerBalance ? ownerBalance : assetBalance;
    }

/******************************************************************************************************************************************/
/**************************************************************** Internal ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @notice Stake any amount of wNXM. 
     * @dev All decisions on pools, amounts, tranches are manual.
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
        tokenIdToTranches[tokenId].push(_trancheId);
        // if new nft token is minted we need to keep track of
        // tokenId and poolAddress inorder to calculate assets
        // under management
        if (tokenIdToPool[tokenId] == address(0)) {
            tokenIds.push(tokenId);
            tokenIdToPool[tokenId] = _poolAddress;
        }
    }

    /**
     * @notice Withdraw any Nxm we can from the staking pool.
     * @return amount The amount of funds that are being withdrawn.
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
        IWNXM(address(wNxm)).wrap(amount);
    }

    /**
     * @notice Used to mint a new Uni V3 position using funds from the stNXM pool. Only used once.
     * @dev When minting, wNXM is added to the pool from here but stNXM is minted directly to the pool.
     *      Infinite amount of stNXM can be minted, only wNXM held by the contract can be added.
     * @param amount0ToAdd wNXM amount to add in the new position.
     * @param amount1ToAdd Amount of stNXM to mint to the Uni pool.
     * @param _tickLower Low tick of the new position.
     * @param _tickUpper High tick of the new position.
     */
    function _mintNewPosition(uint256 amount0ToAdd, uint256 amount1ToAdd, int24 _tickLower, int24 _tickUpper)
        internal
    {
        // make a better initializer
        require(msg.sender == owner(), "May only be minted on initialization.");

        // 1) sort tokens & map amounts
        (address t0, address t1) = address(wNxm) < address(this)
            ? (address(wNxm), address(this))
            : (address(this), address(wNxm));
        uint256 a0 = t0 == address(wNxm) ? amount0ToAdd : amount1ToAdd;
        uint256 a1 = t0 == address(wNxm) ? amount1ToAdd : amount0ToAdd;

        wNxm.approve(address(nfp), amount0ToAdd);
        _mint(address(this), amount1ToAdd);
        _approve(address(this), address(nfp), amount1ToAdd);

        INonfungiblePositionManager.MintParams memory params =
        INonfungiblePositionManager.MintParams({
            token0: t0,
            token1: t1,
            fee: 500,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: amount0ToAdd,
            amount1Desired: amount1ToAdd,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, , , uint256 amount1) = nfp.mint(params);
        dexTokenIds.push(tokenId);

        // Get rid of any stNXM tokens.
        if (amount1 < amount1ToAdd) {
            uint256 refund = amount1ToAdd - amount1;
            _burn(address(this), refund);
        }
    }

/******************************************************************************************************************************************/
/**************************************************************** Administrative ****************************************************************/
/******************************************************************************************************************************************/

    /**
     * @notice Owner can pause the contract at any time. This is used in case a hack occurs and slashing must happen before withdrawals.
     * @dev Ideally a Nexus-owned multisig has control over the contract so a malicious owner cannot permanently pause.
     * Make sure pause has breaks in between pauses so a malicious owner cannot keep it paused forever
     */
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /**
     * @notice Owner may change the amount of delay required for a withdrawal.
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
        require(token != address(wNxm) && token != address(this), "Cannot rescue NXM or stNXM.");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

}