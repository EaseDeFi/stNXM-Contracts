pragma solidity ^0.8.26;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PositionValue} from "@uniswap/v3-periphery/contracts/libraries/PositionValue.sol";

import {Ownable} from "../general/Ownable.sol";
import {ERC721TokenReceiver} from "../general/ERC721TokenReceiver.sol";

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IStakingPool, INxmMaster} from "../interfaces/INexusMutual.sol";
import {IMorpho, MarketParams, Position, Market, Id} from "../interfaces/IMorpho.sol";
import {IWNXM} from "../interfaces/IWNXM.sol";

contract StNXM is ERC4626Upgradeable, ERC721TokenReceiver, Ownable {
    using SafeERC20 for IERC20;

    struct WithdrawalRequest {
        uint48 requestTime;
        uint104 assets;
        uint104 shares;
    }

    event Deposit(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event WithdrawRequested(
        address indexed user, uint256 share, uint256 asset, uint256 requestTime, uint256 withdrawTime
    );
    event Withdrawal(address indexed user, uint256 asset, uint256 share, uint256 timestamp);
    event NxmReward(uint256 reward, uint256 timestamp);

    uint256 private constant DIVISOR = 1000;

    IWNXM public constant wNxm = IWNXM(0x0d438F3b5175Bebc262bF23753C1E53d03432bDE);
    IERC20 public constant nxm = IERC20(0xd7c49CEE7E9188cCa6AD8FF264C1DA2e69D4Cf3B);
    INxmMaster public constant nxmMaster = INxmMaster(0x01BFd82675DBCc7762C84019cA518e701C0cD07e);
    IMorpho public constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    INonfungiblePositionManager public constant nfp =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant irm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    IUniswapV3Pool public dex;
    // Needed for morpho MarketParams
    address public morphoOracle;
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

    // The amount of stake and balance on last update. Needed to make sure a balance change isn't an unstake.
    uint256 private lastStaked;
    uint256 private lastBalance;
    // Whether stNxm is token0 in the dex with wNxm.
    bool private isToken0;

    // Ids for Uniswap NFTs
    uint256[] public dexTokenIds;
    /// @dev record of vaults NFT tokenIds
    uint256[] public tokenIds;
    /// @dev tokenId to risk pool address
    mapping(uint256 => address) public tokenIdToPool;
    mapping(uint256 => uint256[]) public tokenIdToTranches;

    // All withdrawal requests
    mapping(address => WithdrawalRequest) public withdrawals;

    /**
     *
     */
    /**
     * Main ***************************************************************
     */
    /**
     *
     */

    /**
     * @notice Main initializer for the contract.
     * @param _beneficiary Address that will receive admin fees.
     * @param _mintAmount The initial amount to mint that will be put into the arNXM/stNXM token swap contract.
     */
    function initialize(address _beneficiary, uint256 _mintAmount) public initializer {
        __ERC20_init("Staked NXM", "stNXM");
        __ERC4626_init(IERC20(address(wNxm)));
        Ownable.initializeOwnable();

        // Need to mint a certain amount and send it to owner. Maybe just arNXM total supply?
        _mint(owner(), _mintAmount);

        adminPercent = 100;
        beneficiary = _beneficiary;
        withdrawDelay = 2 days;
        isToken0 = address(this) < address(wNxm);

        nxm.approve(address(wNxm), type(uint256).max);
    }

    /**
     * @notice Secondary initializer where addresses are set that can't be set in the first yet.
     * @param _dex The address of the Uni V3 wNXM/stNXM pool.
     * @param _morphoOracle The stNXM oracle contract that returns twap price from the dex.
     * @param _dexDeposit The amount of funds to initially deposit into the dex (in wNXM, matched with virtual stNXM).
     */
    function initializeExternals(address _dex, address _morphoOracle, uint256 _dexDeposit) external {
        require(msg.sender == owner() && address(dex) == address(0), "Only owner may call, and only call once.");

        dex = IUniswapV3Pool(_dex);
        morphoOracle = _morphoOracle;
        MarketParams memory marketParams =
            MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000);
        morphoId = Id.wrap(keccak256(abi.encode(marketParams)));

        _mintNewPosition(_dexDeposit, -887270, 887270);

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

            for (uint256 tranche = firstTranche; tranche < firstTranche + 8; tranche++) {
                (,, uint256 trancheDeposit,) = IStakingPool(_stakingPool).getDeposit(id, tranche);
                if (trancheDeposit > 0) tokenIdToTranches[id].push(tranche);
            }
        }

        lastBalance = wNxm.balanceOf(address(this));
        lastStaked = stakedNxm();
    }

    /**
     * @notice Update admin fees based on any changes that occurred between last deposit and withdrawal.
     * @dev This is to be used on functions that have balance changes unrelated to rewards within them such as deposit/withdraw.
     */
    modifier update() {
        // Wrap NXM in case rewards were sent to the contract without us knowing
        uint256 nxmBalance = nxm.balanceOf(address(this));
        if (nxmBalance > 0) wNxm.wrap(nxmBalance);

        uint256 balance = wNxm.balanceOf(address(this));
        uint256 staked = stakedNxm();

        // This only happens without another update if rewards have entered the contract.
        if (balance > lastBalance && lastStaked <= staked) {
            adminFees += (balance - lastBalance) * adminPercent / DIVISOR;
        }

        _;

        lastBalance = wNxm.balanceOf(address(this));
        lastStaked = stakedNxm();
    }

    /**
     * @notice Ensure contract is not currently paused.
     */
    modifier notPaused() {
        require(!paused, "Contract is currently paused.");
        _;
    }

    /**
     *
     */
    /**
     * Public ***************************************************************
     */
    /**
     *
     */

    /// We need all of these below to apply the update modifier to them.
    function deposit(uint256 assets, address receiver) public override update returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override update returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override update returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override update returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @dev Underlying withdraw functions differently from ERC4626 because of the required delay.
     * @param caller The caller of the function to withdraw.
     * @param assets The amount of wNXM being withdrawn.
     * @param shares The amount of stNXM being withdrawn.
     */
    function _withdraw(address caller, address, address, uint256 assets, uint256 shares) internal override notPaused {
        require(
            _convertToAssets(pending + shares, Math.Rounding.Floor) <= wNxm.balanceOf(address(this)),
            "Not enough NXM available for withdrawal."
        );

        pending += shares;
        _transfer(caller, address(this), shares);
        WithdrawalRequest memory prevWithdrawal = withdrawals[caller];

        // If one withdraw happens before another is finalized, it adds the amounts but resets the request time.
        withdrawals[caller] = WithdrawalRequest(
            uint48(block.timestamp), prevWithdrawal.assets + uint104(assets), prevWithdrawal.shares + uint104(shares)
        );

        emit WithdrawRequested(caller, shares, assets, block.timestamp, block.timestamp + withdrawDelay);
    }

    /// Need to override here so that we can add the update modifier.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Finalize a withdraw request after the withdraw delay ends.
     * @dev Only one withdraw request can be active at a time for a user so this needs no extra params.
     * @param _user The address to finalize withdrawal for.
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
        wNxm.transfer(_user, assets);
        emit Withdrawal(_user, assets, shares, block.timestamp);
    }

    /**
     * @notice Collect all rewards from Nexus staking pool and from dex.
     * @dev These rewards stream to users over the reward duration. Can be called by anyone once the duration is over.
     */
    function getRewards() external update returns (uint256 rewards) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            rewards += _withdrawFromPool(tokenIdToPool[tokenId], tokenId, false, true, tokenIdToTranches[tokenId]);
        }

        // Collect fees from the dex. Compounds back into stNXM value.
        rewards += collectDexFees();

        // Update for any changes since last interaction
        // We don't run the modifier because changes within the function should add to admin fees.
        adminFees += rewards * adminPercent / DIVISOR;

        emit NxmReward(rewards, block.timestamp);
    }

    /**
     * @notice Collect fees from the Uni V3 pool
     * @dev Does not have update because it's called within getRewards.
     */
    function collectDexFees() public returns (uint256 rewards) {
        for (uint256 i = 0; i < dexTokenIds.length; i++) {
            // amount0 is wNXM
            // amount1 is stNXM
            (uint256 amount0, uint256 amount1) = nfp.collect(
                INonfungiblePositionManager.CollectParams(
                    dexTokenIds[i],
                    address(this), // recipient of the fees
                    type(uint128).max, // maximum amount of amount0
                    type(uint128).max // maximum amount of amount1
                )
            );

            (uint256 stNxmAmount, uint256 wNxmAmount) = isToken0 ? (amount0, amount1) : (amount1, amount0);

            // Burn the stNXM fees.
            if (stNxmAmount > 0) _burn(address(this), stNxmAmount);
            rewards += wNxmAmount;
        }
    }

    /**
     * @notice Unstake NXM from pools once the allocation has expired. Can be called by anyone.
     * @param _tokenId Staking NFT token id.
     * @param _trancheIds Tranches to unstake from.
     */
    function unstakeNxm(uint256 _tokenId, uint256[] memory _trancheIds) external update {
        _withdrawFromPool(tokenIdToPool[_tokenId], _tokenId, true, false, _trancheIds);
    }

    /**
     * @notice Check and reset all active tranches for each NFT ID. Can be called by anyone.
     */
    function resetTranches() public update {
        // Use the most recently expired tranche
        uint256 firstTranche = (block.timestamp / 91 days) - 1;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 id = tokenIds[i];
            address _stakingPool = tokenIdToPool[id];
            delete tokenIdToTranches[id];

            for (uint256 tranche = firstTranche; tranche < firstTranche + 9; tranche++) {
                (,, uint256 trancheDeposit,) = IStakingPool(_stakingPool).getDeposit(id, tranche);
                if (trancheDeposit > 0) tokenIdToTranches[id].push(tranche);
            }
        }
    }

    /**
     * @notice Withdraw all fees that have accrued to the admin.
     * @dev Callable by anyone.
     */
    function withdrawAdminFees() external update {
        if (adminFees > 0) wNxm.transfer(beneficiary, adminFees);
        adminFees = 0;
    }

    /**
     *
     */
    /**
     * Owner Functionality ***************************************************************
     */
    /**
     *
     */

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
        address stakingPool = tokenIdToPool[_tokenId];

        if (_topUpAmount > 0) {
            wNxm.unwrap(_topUpAmount);
            nxm.approve(nxmMaster.getLatestAddress("TC"), _topUpAmount);
        }

        IStakingPool(stakingPool).extendDeposit(_tokenId, _initialTrancheId, _newTrancheId, _topUpAmount);
    }

    /**
     * @notice Deposit wNXM to Morpho to be lent out with stNXM as collateral.
     * @param _assetAmount Amount of wNXM to be lent out.
     */
    function morphoDeposit(uint256 _assetAmount) external onlyOwner update {
        wNxm.approve(address(morpho), _assetAmount);
        morpho.supply(
            MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000),
            _assetAmount,
            0,
            address(this),
            ""
        );
    }

    /**
     * @notice Redeem Morpho assets to get wNXM back into the pool.
     * @param _shareAmount Amount of Morpho shares to redeem for wNXM.
     */
    function morphoRedeem(uint256 _shareAmount) external onlyOwner update {
        morpho.withdraw(
            MarketParams(address(wNxm), address(this), morphoOracle, irm, 625000000000000000),
            0,
            _shareAmount,
            address(this),
            address(this)
        );
    }

    /**
     * @notice Decrease liquidity in a token that the vault owns.
     * @param tokenId ID of the Uni NFT that we're removing from.
     * @param liquidity Amount of liquidity to remove from the token.
     */
    function decreaseLiquidity(uint256 tokenId, uint128 liquidity) external onlyOwner update {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        nfp.decreaseLiquidity(params);
        (uint256 amount0, uint256 amount1) = nfp.collect(
            INonfungiblePositionManager.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max)
        );
        uint256 stNxmAmount = isToken0 ? amount0 : amount1;

        // Burn stNXM that was removed.
        if (stNxmAmount > 0) _burn(address(this), stNxmAmount);

        // If we're removing all liquidity, remove from tokenIds.
        (,,,,,,, uint128 tokenLiq,,,,) = nfp.positions(tokenId);
        if (tokenLiq == 0) {
            for (uint256 i = 0; i < dexTokenIds.length; i++) {
                if (tokenId == dexTokenIds[i]) {
                    dexTokenIds[i] = dexTokenIds[dexTokenIds.length - 1];
                    dexTokenIds.pop();
                }
            }
        }
    }

    /**
     *
     */
    /**
     * View ***************************************************************
     */
    /**
     *
     */

    /**
     * @notice Get total assets that the vault holds.
     * @dev This is important to overwrite because it must include wNXM currently being held,
     *       NXM currently being staked, wNXM being lent out, wNXM being used as liquidity,
     *       and account for tokens currently being withdrawn and rewards being distributed.
     *       This also does not always account for exact admin fees, so be wary of that.
     */
    function totalAssets() public view override returns (uint256) {
        // Add staked NXM, wNXM in the contract, wNXM in the dex and Morpho, subtract the admin fees.
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

            uint256 activeStake = IStakingPool(pool).getActiveStake();
            uint256 stakeSharesSupply = IStakingPool(pool).getStakeSharesSupply();

            // Used to determine if we need to check an expired tranche.
            uint256 currentTranche = block.timestamp / 91 days;
            for (uint256 j = 0; j < trancheIds.length; j++) {
                uint256 tranche = trancheIds[j];
                (,, uint256 stakeShares,) = IStakingPool(pool).getDeposit(token, tranche);

                if (tranche < currentTranche) {
                    (, uint256 amountAtExpiry, uint256 sharesAtExpiry) = IStakingPool(pool).getExpiredTranche(tranche);
                    // Pool has been properly expired here.
                    if (sharesAtExpiry > 0) assets += (amountAtExpiry * stakeShares) / sharesAtExpiry;
                    // The tranche ended but expirations have not been processed.
                    else assets += (activeStake * stakeShares) / stakeSharesSupply;
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
        (uint256 assetsAmount,) = dexBalances();
        assets += assetsAmount;
        assets += morphoBalance();
    }

    /**
     * @notice Find balances of both wNXM and stNXM within the Uniswap pool this contract uses.
     */
    function dexBalances() public view returns (uint256 assetsAmount, uint256 sharesAmount) {
        (uint160 sqrtRatio,,,,,,) = dex.slot0();

        for (uint256 i = 0; i < dexTokenIds.length; i++) {
            (uint256 posAmount0, uint256 posAmount1) = PositionValue.total(nfp, dexTokenIds[i], sqrtRatio);

            if (isToken0) {
                sharesAmount += posAmount0;
                assetsAmount += posAmount1;
            } else {
                sharesAmount += posAmount1;
                assetsAmount += posAmount0;
            }
        }
    }

    /**
     * @notice Find the balance (in wNXM) that the vault is lending out on Morpho.
     */
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

    /// Used by the frontend to see which allocations we have.
    /// All we really need to return is amounts from each tranche and separately the amount in each pool
    function trancheAndPoolAllocations()
        external
        view
        returns (uint256[] memory pools, uint256[] memory tokenAmounts, uint256[8] memory trancheAmounts)
    {
        pools = new uint256[](tokenIds.length);
        tokenAmounts = new uint256[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Pool ID is easier for the frontend since the API uses ID directly
            address stakingPool = tokenIdToPool[tokenId];
            uint256 poolId = IStakingPool(stakingPool).getPoolId();
            uint256 activeStake = IStakingPool(stakingPool).getActiveStake();
            uint256 stakeSharesSupply = IStakingPool(stakingPool).getStakeSharesSupply();
            pools[i] = poolId;

            uint256 currentTranche = block.timestamp / 91 days;
            for (uint256 j = 0; j < 8; j++) {
                (,, uint256 trancheDeposit,) = IStakingPool(stakingPool).getDeposit(tokenId, currentTranche + j);
                uint256 nxmStake = activeStake * trancheDeposit / stakeSharesSupply;
                trancheAmounts[j] += nxmStake;
                tokenAmounts[i] += nxmStake;
            }
        }
    }

    /**
     *
     */
    /**
     * Internal ***************************************************************
     */
    /**
     *
     */

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
        wNxm.unwrap(_amount);
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
     * @param _poolAddress Address to withdraw from.
     * @param _tokenId The token to withdraw rewards from or unstake.
     * @param _withdrawStake Should we withdraw stake that is past its expiration?
     * @param _withdrawRewards Should we withdraw rewards gotten from cover being sold?
     * @param _trancheIds Tranches to withdraw stake and/or rewards from.
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
        (uint256 withdrawnStake, uint256 withdrawnRewards) =
            pool.withdraw(_tokenId, _withdrawStake, _withdrawRewards, _trancheIds);
        amount = withdrawnStake + withdrawnRewards;
        wNxm.wrap(amount);
    }

    /**
     * @notice Used to mint a new Uni V3 position using funds from the stNXM pool. Only used once.
     * @dev When minting, wNXM is added to the pool from here but stNXM is minted directly to the pool.
     *      Infinite amount of stNXM can be minted, only wNXM held by the contract can be added.
     * @param amountToAdd wNXM and stNXM amount to add in the new position.
     * @param _tickLower Low tick of the new position.
     * @param _tickUpper High tick of the new position.
     */
    function _mintNewPosition(uint256 amountToAdd, int24 _tickLower, int24 _tickUpper) internal {
        // 1) sort tokens & map amounts
        (address t0, address t1) = isToken0 ? (address(this), address(wNxm)) : (address(wNxm), address(this));

        wNxm.approve(address(nfp), amountToAdd);
        _mint(address(this), amountToAdd);
        _approve(address(this), address(nfp), amountToAdd);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: t0,
            token1: t1,
            fee: 500,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: amountToAdd,
            amount1Desired: amountToAdd,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,, uint256 amount0, uint256 amount1) = nfp.mint(params);
        uint256 stNxmAmount = isToken0 ? amount0 : amount1;

        // Get rid of any extra stNXM tokens.
        if (stNxmAmount < amountToAdd) {
            uint256 refund = amountToAdd - stNxmAmount;
            _burn(address(this), refund);
        }

        dexTokenIds.push(tokenId);
    }

    /**
     *
     */
    /**
     * Administrative ***************************************************************
     */
    /**
     *
     */

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
     */
    function changeBeneficiary(address _newBeneficiary) external onlyOwner {
        beneficiary = _newBeneficiary;
    }

    /**
     * @dev Remove token id from tokenIds array
     * @param _index Index of the tokenId to remove
     */
    function removeTokenIdAtIndex(uint256 _index) external onlyOwner {
        uint256 tokenId = tokenIds[_index];
        tokenIds[_index] = tokenIds[tokenIds.length - 1];
        tokenIds.pop();
        // remove mapping to pool
        delete tokenIdToPool[tokenId];
    }

    /**
     * @dev Rescue tokens locked in contract
     * @param token address of token to withdraw
     */
    function rescueToken(address token) external onlyOwner {
        require(
            token != address(wNxm) && token != address(nxm) && token != address(this),
            "Cannot rescue wNXM, NXM or stNXM."
        );
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }
}
