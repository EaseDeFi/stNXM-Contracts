// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/* solhint-disable */

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/interfaces/IERC20.sol";

import "../../contracts/interfaces/INexusMutual.sol";
import "../../contracts/interfaces/IarNXMVault.sol";
import "../../contracts/interfaces/INonfungiblePositionManager.sol";
import "../../contracts/interfaces/IMorpho.sol";
import "../../contracts/interfaces/IMorphoFactory.sol";
import "../../contracts/interfaces/IUniswapFactory.sol";
import "../../contracts/interfaces/IWNXM.sol";
import "../../contracts/libraries/v3-core/IUniswapV3Pool.sol";
import "../../contracts/libraries/v3-core/ISwapRouter.sol";

// import new contracts
import {StNXM} from "../../contracts/core/stNXM.sol";
import {TokenSwap} from "../../contracts/core/stNxmSwap.sol";
import {StOracle} from "../../contracts/core/stNxmOracle.sol";

contract stNxmTest is Test {
    error InvalidStakingPoolForToken();

    uint256 currentFork;

    IWNXM wNxm = IWNXM(0x0d438F3b5175Bebc262bF23753C1E53d03432bDE);
    IERC20 arNxm = IERC20(0x1337DEF18C680aF1f9f45cBcab6309562975b1dD);
    address arNxmVault = 0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4;    
    StNXM stNxm;

    IStakingNFT stakingNFT = IStakingNFT(0xcafea508a477D94c502c253A58239fb8F948e97f);
    INonfungiblePositionManager nfp = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    TokenSwap stNxmSwap;
    StOracle stNxmOracle;
    IUniswapV3Pool dex;

    address[] riskPools = [0x5A44002A5CE1c2501759387895A3b4818C3F50b3, 0x5A44002A5CE1c2501759387895A3b4818C3F50b3, 0x34D250E9fA70748C8af41470323B4Ea396f76c16];
    uint256[] tokenIds = [214, 215, 242];

    address multisig = 0x1f28eD9D4792a567DaD779235c2b766Ab84D8E33;
    address wnxmWhale = 0x741AA7CFB2c7bF2A1E7D4dA2e3Df6a56cA4131F3;
    address uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address oracle = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nxmMaster = 0x01BFd82675DBCc7762C84019cA518e701C0cD07e;
    address nxm = 0xd7c49CEE7E9188cCa6AD8FF264C1DA2e69D4Cf3B;
    address irm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    address arnxmWhale = 0x28a55C4b4f9615FDE3CDAdDf6cc01FcF2E38A6b0;

    function setUp() public {
        currentFork = vm.createFork("https://mainnet.infura.io/v3/0c7537c516c74815abb1b4d3ad076a2e", 23665310);
        vm.selectFork(currentFork);

        // Create new stNxm contract here
        stNxm = new StNXM();

        // 100k ether is mint amount and will be equal to arNXM total assets.
        stNxm.initialize(multisig, 100000 ether);

        // Deploy and fill swap here.
        stNxmSwap = new TokenSwap(address(stNxm), address(arNxm));
        
        stNxm.transfer(address(stNxmSwap), 100000 ether);

        // And create and initialize uniswap pool with a 1:1 exchange
        dex = IUniswapV3Pool(IUniswapFactory(uniswapFactory).createPool(address(stNxm), address(wNxm), 500));
        IUniswapV3Pool(dex).initialize(79228162514264337593543950336);

        // Create oracle here
        stNxmOracle = new StOracle(address(dex), address(wNxm), address(stNxm));

        // Create Morpho pool here
        morpho.createMarket(MarketParams(address(wNxm), address(stNxm), address(stNxmOracle), irm, 625000000000000000));

        // Finalize NFT transfers
        vm.startPrank(arNxmVault);
        stakingNFT.transferFrom(arNxmVault, address(stNxm), 214);
        stakingNFT.transferFrom(arNxmVault, address(stNxm), 215);
        stakingNFT.transferFrom(arNxmVault, address(stNxm), 242);
        stakingNFT.transferFrom(arNxmVault, address(stNxm), 3);
        stakingNFT.transferFrom(arNxmVault, address(stNxm), 4);

        uint256 bal = IERC20(nxm).balanceOf(arNxmVault);
        IERC20(nxm).approve(address(wNxm), bal);
        wNxm.wrap(bal);
        wNxm.transfer(address(stNxm), bal);

        // We need to transfer arNXM membership to stNXM
        INxmMaster(0x055CC48f7968FD8640EF140610dd4038e1b03926).switchMembership(address(stNxm));
        vm.stopPrank();

        // Finalize initialization with dex info.
        stNxm.initializeExternals(address(dex), address(stNxmOracle), 1000 ether);

        // Supply wNxm using stNxm
        stNxm.morphoDeposit(1000 ether);

        stNxm.transferOwnership(multisig);
        vm.startPrank(multisig);
        stNxm.receiveOwnership();
        vm.stopPrank();
    }

    // Let's just use these tests to also test oracle and swap

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositWNXM(uint256 depositAmt, address user) public {
        vm.startPrank(user);
        // approve wnxm
        wNxm.approve(address(stNxm), depositAmt);
        stNxm.deposit(depositAmt, user);
        vm.stopPrank();
    }

    function withdrawWNXM(uint256 amount, address user) public {
        vm.startPrank(user);
        stNxm.approve(address(stNxm), amount);
        stNxm.redeem(amount, user, user); 
        vm.stopPrank();
    }

    function finalizeWithdrawal(address user) public {
        vm.startPrank(user);
        stNxm.withdrawFinalize(user);
        vm.stopPrank();
    }

    function stakeNxm(uint256 amount, address poolAddress, uint256 trancheId, uint256 requestTokenId) public {
        vm.startPrank(multisig);
        stNxm.stakeNxm(amount, poolAddress, trancheId, requestTokenId);
        vm.stopPrank();
    }

    function unstakeNxm(uint256 tokenId, uint256[] memory trancheIds) public {
        vm.startPrank(multisig);
        stNxm.unstakeNxm(tokenId, trancheIds);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitializedValues() public {
        // check if stakingNFT is initialized properly
        //require(stNxm.stakingNFT() == address(stakingNFT), "staking nft not setup");
        // check if token id's are initialized properly
        //require(stNxm.tokenIds(0) == 3);
        //require(stNxm.tokenIds(1) == 4);

        // check if risk pools are initialized properly
        //require(stNxm.tokenIdToPool(3) == riskPools[0]);
        //require(stNxm.tokenIdToPool(4) == riskPools[1]);
    }

    function testAum() public view {
        uint256 aum = stNxm.totalAssets();
        uint256 arnxmAum = 113776349578321093826437;
        require(aum < arnxmAum + 50 ether && aum > arnxmAum - 50 ether, "Incorrect Aum");
    }

    // Test the staked amount if nothing changes other than a stake expiring.
    function testStakeAfterExpiry() public {
        uint256 startStake = stNxm.stakedNxm();
        vm.warp(block.timestamp + 100 days);
        IStakingPool(riskPools[0]).processExpirations(true);
        uint256 endStake = stNxm.stakedNxm();
        require(startStake == endStake, "Ending stake is not equal to starting stake.");
    }

    function testWNXMDeposit() public {
        uint256 depositAmt = 10e18;
        uint256 expectedStNXMAmt = stNxm.convertToShares(depositAmt);
        uint256 stNxmBalBefore = stNxm.balanceOf(wnxmWhale);
        // deposit to vault
        depositWNXM(depositAmt, wnxmWhale);

        uint256 stNxmBalAfter = stNxm.balanceOf(wnxmWhale);

        require((stNxmBalAfter - stNxmBalBefore) == expectedStNXMAmt, "minted value off");
    }

    function testWithdrawWithoutFee() public {
        depositWNXM(10e18, wnxmWhale);
        uint256 whaleStNxmBal = stNxm.balanceOf(wnxmWhale);
        uint256 totalPendingBefore = stNxm.pending();
        uint256 vaultsStNxmBalBefore = stNxm.balanceOf(address(stNxm));

        withdrawWNXM(whaleStNxmBal, wnxmWhale);
        uint256 vaultsStNxmBalAfter = stNxm.balanceOf(address(stNxm));
        uint256 totalPendingAfter = stNxm.pending();

        require((vaultsStNxmBalAfter - vaultsStNxmBalBefore) == whaleStNxmBal, "arnxm transfer to vault error");

        require(
            (totalPendingAfter - totalPendingBefore) == whaleStNxmBal, "pending not updated"
        );
    }

    function testFinalizeWithdrawal() public {
        // deposit to vault
        depositWNXM(10e18, wnxmWhale);
        uint256 withdrawAmt = stNxm.balanceOf(wnxmWhale);
        uint256 expectedWNXM = stNxm.convertToAssets(withdrawAmt);
        withdrawWNXM(withdrawAmt, wnxmWhale);
        uint256 wnxmBalBefore = wNxm.balanceOf(wnxmWhale);
        uint256 stnxmBalBefore = stNxm.balanceOf(address(stNxm));
        // fast forward 7 days
        vm.warp(block.timestamp + 2 days + 1 hours);
        finalizeWithdrawal(wnxmWhale);
        uint256 stnxmBalAfter = stNxm.balanceOf(address(stNxm));
        uint256 wnxmBalAfter = wNxm.balanceOf(wnxmWhale);

        // check difference in arnxm balance
        require(stnxmBalBefore - stnxmBalAfter == withdrawAmt, "stnxm bal diff failed");
        // check difference in wnxm balance
        require(wnxmBalAfter - wnxmBalBefore == expectedWNXM, "wnxm bal diff failed");
    }

    function testCollectReward_success() public {
        // Set initial rewards
        stNxm.getRewards();
        uint256 nxmBalBefore = wNxm.balanceOf(address(stNxm));
        vm.warp(block.timestamp + 7 days);
        stNxm.getRewards();
        uint256 nxmBalAfter = wNxm.balanceOf(address(stNxm));
        require(nxmBalAfter > nxmBalBefore, "Rewards were not withdrawn.");
    }

    function testStakeNXM() public {
        // add nxm to nxmvault from nxm whale
        depositWNXM(1000e18, wnxmWhale);
        // first active tranche Id
        uint256 trancheId = 224;
        uint256 amountToStake = 1000e18;

        IStakingPool stakingPool = IStakingPool(riskPools[0]);
        (uint256 stakeSharesBefore, uint256 rewardSharesBefore) = stakingPool.getTranche(trancheId);

        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        uint256 aumBefore = stNxm.totalAssets();

        // deposit to staking pool
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[0]);

        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));
        uint256 aumAfter = stNxm.totalAssets();

        // aum increases by 1 uinits so >= is used instead of ==
        require(aumAfter > aumBefore - 1 ether && aumAfter < aumBefore + 1 ether, "aum should not change");
        require((vaultNXMBalBefore - vaultNXMBalAfter) == amountToStake, "nxm not staked");

        (uint256 stakeSharesAfter, uint256 rewardSharesAfter) = stakingPool.getTranche(trancheId);
        // stake shares should increase
        require(stakeSharesAfter > stakeSharesBefore, "stake shares not updated");
        // reward shares should increase
        require(rewardSharesAfter > rewardSharesBefore, "reward shares not updated");
    }

    function testStakeNXMWithInvalidStakingPoolToken() public {
        // add nxm to nxmvault from nxm whale
        vm.startPrank(wnxmWhale);
        wNxm.transfer(address(stNxm), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint256 trancheId = 224;
        uint256 amountToStake = 1000e18;

        // deposit to staking pool
        vm.expectRevert();

        // stake with invalid staking pool for token
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[2]);
    }

    function testStakeNXMAndGetNewNFT() public {
        // add nxm to nxmvault from nxm whale
        depositWNXM(1000e18, wnxmWhale);
        // first active tranche Id
        uint256 trancheId = 224;
        uint256 amountToStake = 1000e18;
        uint256 stakingNFTBalBefore = stakingNFT.balanceOf(address(stNxm));

        uint256 aumBefore = stNxm.totalAssets();
        // array should only have 3 elements
        vm.expectRevert();
        stNxm.tokenIds(3);

        // deposit to staking pool and get new nft (*0 as tokenID mints new one)
        stakeNxm(amountToStake, riskPools[0], trancheId, 0);

        uint256 aumAfter = stNxm.totalAssets();

        uint256 stakingNFTBalAfter = stakingNFT.balanceOf(address(stNxm));

        // should mint new nft
        require((stakingNFTBalAfter - stakingNFTBalBefore) == 1, "nft not minted");
        uint256 mintedNFTTokenId = stakingNFT.totalSupply();
        require(
            stakingNFT.ownerOf(mintedNFTTokenId) == address(stNxm), "arNXM vault should be owner of new nft"
        );

        INFTDescriptor nftDescriptor = INFTDescriptor(stakingNFT.nftDescriptor());

        (, uint256 actualStaked,) = nftDescriptor.getActiveDeposits(mintedNFTTokenId, riskPools[0]);
        // total staked returned by nexus is little bit less than actual staked
        require(actualStaked >= (amountToStake - 1e12), "wrong total staked");

        // aum should be equal to or greater than actual staked
        require(aumAfter > aumBefore - 1 ether && aumAfter < aumBefore + 1 ether, "aum should be >= aum before");

        // check if new tokenId was added to tokenIds array
        uint256 newTokenId = stNxm.tokenIds(3);
        require(newTokenId == mintedNFTTokenId, "wrong token id");

        // check if new token id was mapped to risk pool
        address stakedRiskPool = stNxm.tokenIdToPool(newTokenId);
        require(stakedRiskPool == riskPools[0], "wrong risk pool");
    }

    function testUnstakeNXM() public {
        uint256 trancheId = 224;
        uint256[] memory trancheIds = new uint256[](1);
        // approximation
        uint256 expectedUnstakeAmount = 12903e18;
        trancheIds[0] = trancheId;
        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        vm.warp(block.timestamp + 92 days);
        unstakeNxm(tokenIds[1], trancheIds);
        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));
        require(vaultNXMBalAfter > (vaultNXMBalBefore + expectedUnstakeAmount) - 1 ether, "nxm transfer failed");
    }

    function testUnstakeNXMFail() public {
        uint256 trancheId = 224;
        uint256[] memory trancheIds = new uint256[](1);
        trancheIds[0] = trancheId;
        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        unstakeNxm(tokenIds[0], trancheIds);
        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));

        // as tranche has not expired it should not unstake 0 NXM
        require(vaultNXMBalAfter == vaultNXMBalBefore, "should not unstake");
    }

    function testRemoveTokenId() public {
        // index 1 means we have 2 tokenIds
        uint256 tokenIdAtIndex0Before = stNxm.tokenIds(0);

        require(tokenIdAtIndex0Before == tokenIds[0], "wrong token id");

        // as tokenIds length is 2 this should not revert
        stNxm.tokenIds(1);

        address riskPoolBefore = stNxm.tokenIdToPool(tokenIdAtIndex0Before);

        // remove one of tokenIds
        vm.startPrank(multisig);
        stNxm.removeTokenIdAtIndex(0);
        vm.stopPrank();

        // as tokenIds length is 3 this should revert
        vm.expectRevert();
        stNxm.tokenIds(2);

        address riskPoolAfter = stNxm.tokenIdToPool(tokenIdAtIndex0Before);

        require(riskPoolBefore != riskPoolAfter, "wrong risk pool");
        require(riskPoolAfter == address(0), "risk pool should be 0x0");
        uint256 tokenIdAtIndex0After = stNxm.tokenIds(0);

        require(tokenIdAtIndex0After != tokenIdAtIndex0Before, "token id at index should change");
    }

    function testWithdrawFromUni() public { 
        uint256 balBefore = wNxm.balanceOf(address(stNxm));
        uint256 tsBefore = stNxm.totalSupply();
        uint256 dexTokenId = stNxm.dexTokenIds(0);
        (,,,,,,,uint128 liquidity,,,,) = nfp.positions(dexTokenId);
        vm.startPrank(multisig);
        stNxm.decreaseLiquidity(dexTokenId, liquidity);
        vm.stopPrank();
        // Check increase here
        uint256 balAfter = wNxm.balanceOf(address(stNxm));
        uint256 tsAfter = stNxm.totalSupply();
        require(balAfter > balBefore, "Balance did not increase when liquidity was withdrawn.");
        require(tsBefore == tsAfter, "Total supply has changed when it shouldn't!");
    }

    function testMorpho() public { 
        MarketParams memory marketParams = MarketParams(address(wNxm), address(stNxm), address(stNxmOracle), irm, 625000000000000000);
        Id morphoId = Id.wrap(keccak256(abi.encode(marketParams)));

        Position memory pos = morpho.position(morphoId, address(stNxm));

        vm.startPrank(multisig);
        stNxm.morphoDeposit(1000 ether);
        vm.stopPrank();

        pos = morpho.position(morphoId, address(stNxm));
        require(pos.supplyShares > 0, "New assets did not increase.");

        vm.startPrank(multisig);
        stNxm.morphoRedeem(pos.supplyShares);
        vm.stopPrank();

        pos = morpho.position(morphoId, address(stNxm));

        require(pos.supplyShares == 0, "New assets did not return to normal.");
    }

    function testResetTranches() public {
        stakeNxm(1000000000000000000, riskPools[0], 230, tokenIds[0]);
        stNxm.resetTranches();
        uint256 newTranche = stNxm.tokenIdToTranches(214, 2);
        require(newTranche == 230, "Tranche not reset correctly.");
    }

    function testWithdrawAdminFees() public {
        // Start with an update
        stNxm.withdrawAdminFees();

        // Test with simple wNxm transfer to the contract.
        uint256 adminBalanceBefore = wNxm.balanceOf(multisig);
        vm.startPrank(wnxmWhale);
        wNxm.transfer(address(stNxm), 1 ether);
        vm.stopPrank();
        stNxm.withdrawAdminFees();
        uint256 adminBalanceAfter = wNxm.balanceOf(multisig);

        require (adminBalanceAfter - adminBalanceBefore > 0.099 ether, "Incorrect amount withdrawn.");

        // Check with getRewards being called.
        vm.warp(block.timestamp + 7 days);
        adminBalanceBefore = wNxm.balanceOf(multisig);
        stNxm.getRewards();
        stNxm.withdrawAdminFees();
        adminBalanceAfter = wNxm.balanceOf(multisig);
        require (adminBalanceAfter > adminBalanceBefore, "Incorrect amount withdrawn 2.");
    }

    function testWithdrawDexFees() public { 
        // Make a random uniswap exchange so there are fees in the pool.
        vm.startPrank(wnxmWhale);
        wNxm.approve(address(swapRouter), 1 ether);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(address(wNxm), address(stNxm), 500, wnxmWhale, 1000000000000000, 1 ether, 0, 0);
        swapRouter.exactInputSingle(params);
        vm.stopPrank();

        uint256 balBefore = wNxm.balanceOf(address(stNxm));
        stNxm.collectDexFees();
        uint256 balAfter = wNxm.balanceOf(address(stNxm));
        require(balAfter > balBefore, "No fees were withdrawn.");
    }

    function testPause() public {
        depositWNXM(2 ether, wnxmWhale);
        withdrawWNXM(1 ether, wnxmWhale);
        vm.warp(block.timestamp + 2 days + 1 hours);
        
        vm.startPrank(multisig);
        stNxm.togglePause();
        vm.stopPrank();

        vm.expectRevert();
        finalizeWithdrawal(wnxmWhale);
    }

    function testTokenSwap() public {
        vm.startPrank(arnxmWhale);
        arNxm.approve(address(stNxmSwap), 1 ether);
        stNxmSwap.swap(1 ether);
        vm.stopPrank();
        uint256 balance = stNxm.balanceOf(arnxmWhale);
        require(balance == 956860757679165373, "Swap didn't execute correctly.");
    }

    
    function testOracle() public {
        //uint256 price = stNxmOracle.price();
        //require(price == 1 ether, "Incorrect starting price.");
        uint256 price;

        // Make a random uniswap exchange so there are fees in the pool.
        vm.startPrank(wnxmWhale);
        wNxm.approve(address(swapRouter), 1 ether);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(address(wNxm), address(stNxm), 500, wnxmWhale, 1000000000000000, 1 ether, 0, 0);
        swapRouter.exactInputSingle(params);
        vm.stopPrank();

        vm.warp(block.timestamp + 180000);
        price = stNxmOracle.price();
        require(price > 1 ether, "Incorrect ending price on oracle.");

        // Make a random uniswap exchange so there are fees in the pool.
        vm.startPrank(wnxmWhale);
        wNxm.approve(address(swapRouter), 10000 ether);
        params = ISwapRouter.ExactInputSingleParams(address(wNxm), address(stNxm), 500, wnxmWhale, 1000000000000000, 1 ether, 0, 0);
        swapRouter.exactInputSingle(params);
        vm.stopPrank();

        vm.warp(block.timestamp + 1800);
        vm.expectRevert();
        price = stNxmOracle.price();
    }

}
