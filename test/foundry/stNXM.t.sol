// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/* solhint-disable */

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/interfaces/IERC20.sol";

import "../../contracts/interfaces/INexusMutual.sol";
import "../../contracts/interfaces/IarNXMVault.sol";
import "../../contracts/interfaces/INonfungiblePositionManager.sol";
import "../../contracts/interfaces/IMorpho.sol";
import "../../contracts/libraries/v3-core/IUniswapV3Pool.sol";

// import new contracts
import {StNXM} from "../../contracts/core/stNXM.sol";
import {TokenSwap} from "../../contracts/core/stNxmSwap.sol";
import {StOracle} from "../../contracts/core/stNxmOracle.sol";

contract stNxmTest is Test {
    error InvalidStakingPoolForToken();

    uint256 currentFork;

    IERC20 wNxm = IERC20(0x0d438F3b5175Bebc262bF23753C1E53d03432bDE);
    StNXM stNxm;

    IStakingNFT stakingNFT = IStakingNFT(0xcafea508a477D94c502c253A58239fb8F948e97f);
    INonfungiblePositionManager nfp = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IMorpho morpho;
    TokenSwap stNxmSwap;
    StOracle stNxmOracle;
    IUniswapV3Pool dex;

    address[] riskPools = [0x5a44002a5ce1c2501759387895a3b4818c3f50b3, 0x5a44002a5ce1c2501759387895a3b4818c3f50b3, 0x34d250e9fa70748c8af41470323b4ea396f76c16];
    uint256[] tokenIds = [214, 215, 242];

    address multisig = 0x1f28eD9D4792a567DaD779235c2b766Ab84D8E33;
    address wnxmWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address arNXM = 0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4;
    address morphoFactory = 0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb;
    address uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address oracle = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nxmMaster = 0x01BFd82675DBCc7762C84019cA518e701C0cD07e;
    address nxm = 0xd7c49CEE7E9188cCa6AD8FF264C1DA2e69D4Cf3B;
    address irm = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    function setUp() public {
        // Create new stNxm contract here
        stNxm = new StNXM();
        // 100k ether is mint amount and will be equal to arNXM total assets.
        stNxm.initialize(nfp, wNxm, nxm, nxmMaster, 100000 ether);

        // Deploy and fill swap here.
        stNxmSwap = new TokenSwap();
        stNxm.transfer(address(stNxmSwap), 100000 ether);

        // Create Morpho pool here
        morpho = IMorpho(morphoFactory.createMarket(address(wNxm), address(stNxm), address(oracle), irm, 625000000000000000));
        // Supply wNxm using stNxm
        stNxm.morphoDeposit(1000 ether);

        /*PoolKey memory pool = PoolKey({
            currency0: address(wNXM),
            currency1: address(stNxm),
            fee: 500,
            tickSpacing: 10
            //hooks: hookContract
        });*/

        // And create uniswap pool with a 1:1 exchange
        dex = IUniswapV3Pool(uniswapFactory.createPool(address(wNxm), address(stNxm), 79228162514264337593543950336));

        // Finalize intiialization with dex info.
        stNxm.initializeTwo(address(dex), address(morpho), 5000 ether);

        // Create oracle here
        stNxmOracle = new StOracle(address(dex));

        // Finalize NFT transfers
        vm.startPrank(arNXM);
        stakingNFT.transfer(address(stNxm), 214);
        stakingNFT.transfer(address(stNxm), 215);
        stakingNFT.transfer(address(stNxm), 242);
        // Transfer funds here too
        vm.stopPrank();

        currentFork = vm.createFork("https://mainnet.infura.io/v3/0c7537c516c74815abb1b4d3ad076a2e", 23586004);
        vm.selectFork(currentFork);
    }

    // Let's just use these tests to also test oracle and swap

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositWNXM(uint256 depositAmt, address user) public {
        vm.startPrank(user);
        // approve wnxm
        wNxm.approve(address(stNxm), depositAmt);
        stNxm.deposit(depositAmt, address(0), false);
        vm.stopPrank();
    }

    function withdrawWNXM(uint256 amount, address user) public {
        vm.startPrank(user);
        stNxm.approve(address(stNxm), amount);
        stNxm.withdraw(amount); 
        vm.stopPrank();
    }

    function finalizeWithdrawal(address user) public {
        vm.startPrank(user);
        stNxm.withdrawFinalize();
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

    function testAum() public {
        uint256 vaultNXMBalance = wNxm.balanceOf(address(stNxm));
        uint256 aum = stNxm.totalAssets();
        console.log(aum);

        // from data
        //uint256 nxmStakedInAAPool = 27701e18; // approx staked to AA pool
        //uint256 nxmStakedInAAAPool = 83103e18; // approx staked to AAA pool

        //require(aum >= (vaultNXMBalance + nxmStakedInAAPool + nxmStakedInAAAPool), "Incorrect Aum");
    }

    // Test the staked amount if nothing changes other than a stake expiring.
    function testStakeAfterExpiry() public {
        uint256 startStake = stNxm.stakedNxm();
        vm.warp(block.timestamp + 100 days);
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
        uint256 totalPendingBefore = stNxm.totalPending();
        uint256 vaultsStNxmBalBefore = stNxm.balanceOf(address(stNxm));

        withdrawWNXM(whaleStNxmBal, wnxmWhale);
        uint256 vaultsStNxmBalAfter = stNxm.balanceOf(address(stNxm));
        uint256 totalPendingAfter = stNxm.totalPending();

        require((vaultsStNxmBalBefore - vaultsStNxmBalAfter) == whaleStNxmBal, "arnxm transfer to vault error");

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
        uint256 nxmBalBefore = wNxm.balanceOf(address(stNxm));
        stNxm.getRewards();
        uint256 nxmBalAfter = wNxm.balanceOf(address(stNxm));

        require(nxmBalAfter > nxmBalBefore, "Rewards were not withdrawn.");
    }

    function testStakeNXM() public {
        // add nxm to nxmvault from nxm whale
        vm.startPrank(wnxmWhale);
        wNxm.transfer(address(stNxm), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint256 trancheId = 222;
        uint256 amountToStake = 1000e18;

        IStakingPool stakingPool = IStakingPool(riskPools[0]);
        (uint256 stakeSharesBefore, uint256 rewardSharesBefore) = stakingPool.getTranche(trancheId);

        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        uint256 aumBefore = stNxm.aum();

        // deposit to staking pool
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[0]);

        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));
        uint256 aumAfter = stNxm.aum();

        // aum increases by 1 uinits so >= is used instead of ==
        require(aumAfter == aumBefore, "aum should not change");
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
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[1]);
    }

    function testStakeNXMAndGetNewNFT() public {
        // add nxm to nxmvault from nxm whale
        vm.startPrank(wnxmWhale);
        wNxm.transfer(address(stNxm), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint256 trancheId = 224;
        uint256 amountToStake = 1000e18;
        uint256 stakingNFTBalBefore = stakingNFT.balanceOf(address(stNxm));

        uint256 aumBefore = stNxm.totalAssets();
        // array should only have 2 elements
        vm.expectRevert();
        stNxm.tokenIds(2);

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
        require(aumAfter >= aumBefore, "aum should be >= aum before");

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
        uint256 expectedUnstakeAmount = 17000e18;
        trancheIds[0] = trancheId;
        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        vm.warp(block.timestamp + 92 days);
        unstakeNxm(tokenIds[0], trancheIds);
        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));
        require(vaultNXMBalAfter > (vaultNXMBalBefore + expectedUnstakeAmount), "nxm transfer failed");
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

    function testWithdrawNxmFromPool() public {
        uint256 trancheId = 224;
        uint256[] memory trancheIds = new uint256[](1);
        // approx unstake amount
        uint256 expectedUnstakeAmount = 17000e18;
        trancheIds[0] = trancheId;
        uint256 vaultNXMBalBefore = wNxm.balanceOf(address(stNxm));
        vm.warp(block.timestamp + 92 days);
        vm.startPrank(multisig);
        stNxm.withdrawNxm(riskPools[0], tokenIds[0], trancheIds);
        vm.stopPrank();
        uint256 vaultNXMBalAfter = wNxm.balanceOf(address(stNxm));

        require(vaultNXMBalAfter > (vaultNXMBalBefore + expectedUnstakeAmount), "nxm transfer failed");
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

        // as tokenIds length is 1 this should revert
        vm.expectRevert();
        stNxm.tokenIds(1);

        address riskPoolAfter = stNxm.tokenIdToPool(tokenIdAtIndex0Before);

        require(riskPoolBefore != riskPoolAfter, "wrong risk pool");
        require(riskPoolAfter == address(0), "risk pool should be 0x0");
        uint256 tokenIdAtIndex0After = stNxm.tokenIds(0);

        require(tokenIdAtIndex0After != tokenIdAtIndex0Before, "token id at index should change");
    }

    function testWithdrawFromUni() public { 
        uint256 balBefore = wNxm.balanceOf(address(stNxm));
        uint256 tsBefore = stNxm.totalSupply();
        uint256[] memory dexTokenIds = stNxm.dexTokenIds();
        uint256 liquidity = nfp.liquidity();
        stNxm.decreaseLiquidity(dexTokenIds[0], 1);
        // Check increase here
        uint256 balAfter = wNxm.balanceOf(address(stNxm));
        uint256 tsAfter = stNxm.totalSupply();
        require(balAfter > balBefore, "Balance did not increase when liquidity was withdrawn.");
        require(tsBefore == tsAfter, "Total supply has changed when it shouldn't!");
    }

    function testMorpho() public { 
        vm.startPrank(multisig);
        uint256 nxmBal = wNxm.balanceOf(address(stNxm));
        uint256 morphoBal = morpho.balanceOf(address(stNxm));
        stNxm.morphoDeposit(1000 ether);
        require(morpho.balanceOf(address(stNxm)) > morphoBal);
        //require(wNxm.balanceOf)

        stNxm.morphoRedeem(1000 ether);
        require(morpho.balanceOf(address(stNxm)) == 0);
        
        //require()
    }

    // We need to add tests to:
    // 1. Check for active and expired amounts when things expire
    // 2. Check for rewards being withdrawn through other means
    // 3. Confirm dex is correct

    function testResetTranches() public {
        uint256[] memory tranches = stNxm.tokenIdToTranches(1);
        stakeNxm(1, riskPools[0], 224, tokenIds[0]);
        stNxm.resetTranches();
        uint256[] memory newTranches = stNxm.tokenIdToTranches(1);
        require(newTranches[1] == 224, "Tranche not reset correctly.");
    }

    function testWithdrawAdminFees() public {
        // Test with simple wNxm transfer to the contract.
        uint256 adminBalanceBefore = wNxm.balanceOf(multisig);
        wNxm.transfer(address(stNxm), 1 ether);
        stNxm.withdrawAdminFees();
        uint256 adminBalanceAfter = wNxm.balanceOf(multisig);
        require (adminBalanceAfter - adminBalanceBefore == 0.1 ether, "Incorrect amount withdrawn.");

        // Check with getRewards being called.
        vm.warp(block.timestamp + 7 days);
        adminBalanceBefore = wNxm.balanceOf(multisig);
        stNxm.getRewards();
        stNxm.withdrawAdminFees();
        adminBalanceAfter = wNxm.balanceOf(multisig);
        require (adminBalanceAfter > adminBalanceBefore, "Incorrect amount withdrawn.");
    }

    function testWithdrawDexFees() public { 
        // Make dex trades here I guess?
        uint256 balBefore = wNxm.balanceOf(address(stNxm));
        stNxm.collectDexFees();
        uint256 balAfter = wNxm.balanceOf(address(stNxm));
        require(balAfter > balBefore);
    }

    function testPause() public {
        depositWNXM(2 ether, wnxmWhale);
        withdrawWNXM(1 ether, wnxmWhale);
        vm.warp(block.timestamp + 2 days + 1 hours);
        stNxm.togglePause();
        vm.expectRevert(withdrawWNXM(1 ether, wnxmWhale));
        vm.expectRevert(finalizeWithdrawal(wnxmWhale));
    }

    function testTokenSwap() public {
        //arNxm.approve(address(stNxmSwap), 1000 ether);
        stNxmSwap.swap(1 ether);
        uint256 balance = stNxm.balanceOf(wnxmWhale);
        require(balance == 1 ether, "Swap didn't execute correctly.");
    }

    /*
    function testOracle() public {
        uint256 price = stOracle.price();
        require(price == 1 ether, "Incorrect starting price.");
        dex.swap(someamount);
        vm.warp(block.timestamp + 1800);
        uint256 price = stOracle.price();
        require(price > 1 ether, "Incorrect ending price on oracle.");
        dex.swap(hugeamount);
        vm.warp(block.timestamp + 1800);
        vm.expectRevert();
        uint256 price = stOracle.price();
    }*/

    // Do swap tests

    // Do oracle tests

}
