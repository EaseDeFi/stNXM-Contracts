// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/* solhint-disable */

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/interfaces/IERC20.sol";

import "../../contracts/interfaces/INexusMutual.sol";
import "../../contracts/interfaces/IarNXMVault.sol";
// import new contracts
import {arNXMVault} from "../../contracts/core/arNXMVault.sol";

contract ArNxmSetup is Test {
    function setUp() public {
        // connect to arnxm interface
    }
}

contract arNXMValultOldTest is Test {
    error InvalidStakingPoolForToken();

    uint forkBeforePause;
    uint currentFork;
    uint forkBeforeNxmUpgrade;

    IarNXMVault arNXMVaultProxy;
    IERC20 nxm = IERC20(0xd7c49CEE7E9188cCa6AD8FF264C1DA2e69D4Cf3B);
    IERC20 wNXM = IERC20(0x0d438F3b5175Bebc262bF23753C1E53d03432bDE);
    IERC20 arNXM = IERC20(0x1337DEF18C680aF1f9f45cBcab6309562975b1dD);

    IStakingNFT stakingNFT =
        IStakingNFT(0xcafea508a477D94c502c253A58239fb8F948e97f);
    address implAddress;
    address[] riskPools = [
        0x462340b61e2ae2C13f01F66B727d1bFDc907E53e,
        0xed9915e07aF860C3263801E223C9EaB512EB7C09
    ];
    uint[] tokenIds = [3, 4];

    address multisig = 0x1f28eD9D4792a567DaD779235c2b766Ab84D8E33;
    address wnxmWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address nxmWhale = 0x25783B67b5e29c48449163Db19842b8531fddE43;

    function setUp() public {
        arNXMVaultProxy = IarNXMVault(
            0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4
        );
        currentFork = vm.createFork(
            "https://mainnet.infura.io/v3/0c7537c516c74815abb1b4d3ad076a2e"
        );

        forkBeforeNxmUpgrade = vm.createFork(
            "https://mainnet.infura.io/v3/0c7537c516c74815abb1b4d3ad076a2e",
            16799100 - (5 * 60 * 24)
        );

        vm.selectFork(currentFork);
        implAddress = address(new arNXMVault());
        vm.startPrank(multisig);
        arNXMVaultProxy.upgradeTo(implAddress);
        vm.stopPrank();
    }

    function initializeV2() public {
        vm.startPrank(multisig);
        // initialize v2
        arNXMVaultProxy.initializeV2(stakingNFT, tokenIds, riskPools);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function depositWNXM(uint depositAmt, address user) public {
        vm.startPrank(user);
        // approve wnxm
        wNXM.approve(address(arNXMVaultProxy), depositAmt);
        arNXMVaultProxy.deposit(depositAmt, address(0), false);
        vm.stopPrank();
    }

    function depositNXM(uint depositAmt, address user) public {
        vm.startPrank(user);
        // approve wnxm
        nxm.approve(address(arNXMVaultProxy), depositAmt);
        arNXMVaultProxy.deposit(depositAmt, address(0), true);
        vm.stopPrank();
    }

    function withdrawWNXM(uint amount, address user, bool payFee) public {
        vm.startPrank(user);
        arNXM.approve(address(arNXMVaultProxy), amount);
        arNXMVaultProxy.withdraw(amount, payFee);
        vm.stopPrank();
    }

    function finalizeWithdrawal(address user) public {
        vm.startPrank(user);
        arNXMVaultProxy.withdrawFinalize();
        vm.stopPrank();
    }

    function stakeNxm(
        uint amount,
        address poolAddress,
        uint trancheId,
        uint requestTokenId
    ) public {
        vm.startPrank(multisig);
        arNXMVaultProxy.stakeNxm(
            amount,
            poolAddress,
            trancheId,
            requestTokenId
        );
        vm.stopPrank();
    }

    function unstakeNxm(uint tokenId, uint[] memory trancheIds) public {
        vm.startPrank(multisig);
        arNXMVaultProxy.unstakeNxm(tokenId, trancheIds);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateImplementation() public view {
        address implementation = arNXMVaultProxy.implementation();
        require(
            implementation == implAddress,
            "implementation is still address 0"
        );
    }

    function testInitializedValues() public {
        initializeV2();

        // check if stakingNFT is initialized properly
        require(
            arNXMVaultProxy.stakingNFT() == address(stakingNFT),
            "staking nft not setup"
        );
        // check if token id's are initialized properly
        require(arNXMVaultProxy.tokenIds(0) == 3);
        require(arNXMVaultProxy.tokenIds(1) == 4);

        // check if risk pools are initialized properly
        require(arNXMVaultProxy.tokenIdToPool(3) == riskPools[0]);
        require(arNXMVaultProxy.tokenIdToPool(4) == riskPools[1]);
    }

    function testAum() public {
        initializeV2();

        uint vaultNXMBalance = nxm.balanceOf(address(arNXMVaultProxy));
        uint256 aum = arNXMVaultProxy.aum();

        // from data
        uint nxmStakedInAAPool = 27701e18; // approx staked to AA pool
        uint nxmStakedInAAAPool = 83103e18; // approx staked to AAA pool

        require(
            aum >= (vaultNXMBalance + nxmStakedInAAPool + nxmStakedInAAAPool),
            "Incorrect Aum"
        );
    }

    function testCollectV1PendingRewards() public {
        // test existing rewards probably about 24 NXM
        uint nxmBalBefore = nxm.balanceOf(address(arNXMVaultProxy));
        initializeV2();
        uint nxmBalAfter = nxm.balanceOf(address(arNXMVaultProxy));

        require(
            (nxmBalAfter - nxmBalBefore) > 23e18,
            "not able to collect pending rewards"
        );
    }

    function testTokenValues() public {
        // select fork
        vm.selectFork(forkBeforeNxmUpgrade);
        uint nxmValueBefore = arNXMVaultProxy.nxmValue(1e18);
        uint arNxmValueBefore = arNXMVaultProxy.arNxmValue(1e18);
        vm.selectFork(currentFork);
        initializeV2();
        uint nxmValueAfter = arNXMVaultProxy.nxmValue(1e18);
        uint arNxmValueAfter = arNXMVaultProxy.arNxmValue(1e18);
        // since reward nxm is added to the vault nxmValue after should be
        // less than before
        require(
            nxmValueAfter < nxmValueBefore,
            "value should increase after collect reward"
        );
        // for 1 unit of nxm user will get more arnxm
        require(
            arNxmValueAfter > arNxmValueBefore,
            "value should increase after collect reward"
        );
    }

    function testWNXMDeposit() public {
        initializeV2();
        uint depositAmt = 10e18;
        uint expectedArNXMAmt = arNXMVaultProxy.arNxmValue(depositAmt);
        uint arNXMBalBefore = arNXM.balanceOf(wnxmWhale);
        // deposit to vault
        depositWNXM(depositAmt, wnxmWhale);

        uint arNXMBalAfter = arNXM.balanceOf(wnxmWhale);

        require(
            (arNXMBalAfter - arNXMBalBefore) >= expectedArNXMAmt,
            "minted value off"
        );
    }

    function testNXMDeposit() public {
        initializeV2();
        uint depositAmt = 10e18;
        uint expectedArNXMAmt = arNXMVaultProxy.arNxmValue(depositAmt);
        uint arNXMBalBefore = arNXM.balanceOf(nxmWhale);
        // deposit to vault
        depositNXM(depositAmt, nxmWhale);

        uint arNXMBalAfter = arNXM.balanceOf(nxmWhale);

        require(
            (arNXMBalAfter - arNXMBalBefore) >= expectedArNXMAmt,
            "minted value off"
        );
    }

    function testWithdrawWithFee() public {
        initializeV2();
        address user = wnxmWhale;
        depositWNXM(10e18, user);
        uint withdrawAmt = arNXM.balanceOf(user);
        bool withFee = true;

        uint wnxmBalBefore = wNXM.balanceOf(user);
        uint arnxmBalBefore = arNXM.balanceOf(user);
        withdrawWNXM(withdrawAmt, wnxmWhale, withFee);
        uint arnxmBalAfter = arNXM.balanceOf(user);
        uint wnxmBalAfter = wNXM.balanceOf(user);

        // check difference in arnxm balance
        require(
            arnxmBalBefore - arnxmBalAfter == withdrawAmt,
            "arnxm bal diff failed"
        );

        require(wnxmBalAfter > wnxmBalBefore, "wnxm bal diff failed");
    }

    function testWithdrawWithoutFee() public {
        initializeV2();
        depositWNXM(10e18, wnxmWhale);
        uint whaleArNxmBal = arNXM.balanceOf(wnxmWhale);
        bool withFee = false;
        uint vaultsArNxmBalBefore = arNXM.balanceOf(wnxmWhale);
        uint totalPendingBefore = arNXMVaultProxy.totalPending();

        withdrawWNXM(whaleArNxmBal, wnxmWhale, withFee);
        uint vaultsArNxmBalAfter = arNXM.balanceOf(wnxmWhale);
        uint totalPendingAfter = arNXMVaultProxy.totalPending();

        require(
            (vaultsArNxmBalBefore - vaultsArNxmBalAfter) == whaleArNxmBal,
            "arnxm transfer to vault error"
        );

        require(
            (totalPendingAfter - totalPendingBefore) ==
                arNXMVaultProxy.nxmValue(whaleArNxmBal),
            "pending not updated"
        );
    }

    function testFinalizeWithdrawal() public {
        initializeV2();
        // deposit to vault
        depositWNXM(10e18, wnxmWhale);
        uint withdrawAmt = arNXM.balanceOf(wnxmWhale);
        bool withFee = false;
        uint expectedWNXM = arNXMVaultProxy.nxmValue(withdrawAmt);
        withdrawWNXM(withdrawAmt, wnxmWhale, withFee);
        uint wnxmBalBefore = wNXM.balanceOf(wnxmWhale);
        uint arnxmBalBefore = arNXM.balanceOf(address(arNXMVaultProxy));
        // fast forward 7 days
        vm.warp(block.timestamp + 7 days);
        finalizeWithdrawal(wnxmWhale);
        uint arnxmBalAfter = arNXM.balanceOf(address(arNXMVaultProxy));
        uint wnxmBalAfter = wNXM.balanceOf(wnxmWhale);

        // check difference in arnxm balance
        require(
            arnxmBalBefore - arnxmBalAfter == withdrawAmt,
            "arnxm bal diff failed"
        );
        // check difference in wnxm balance
        require(
            wnxmBalAfter - wnxmBalBefore == expectedWNXM,
            "wnxm bal diff failed"
        );
    }

    function testCollectReward_success() public {
        initializeV2();
        uint lastRewardBefore = arNXMVaultProxy.lastReward();
        uint lastRewardCollectedBefore = arNXMVaultProxy.lastRewardTimestamp();
        vm.warp(block.timestamp + 7 days);
        vm.prank(address(1234), address(1234));
        arNXMVaultProxy.getRewardNxm();
        vm.stopPrank();
        uint lastRewardAfter = arNXMVaultProxy.lastReward();
        uint lastRewardCollectedAfter = arNXMVaultProxy.lastRewardTimestamp();

        // as reward for v2 is not active yet lastRewardAfter should be 0
        require(lastRewardAfter == 0, "wrong reward after");

        // as there is an existing lastReward amount in the proxy it should not be 0
        // checking for storage collision as this is upgraded to new impl
        require(lastRewardBefore != 0, "last reward before should be > 0");

        require(
            lastRewardCollectedAfter- lastRewardCollectedBefore >= 7 days,
            "diff of last reward timestamp should be more than 7 days"
        );
    }

    function testCollectReward_fail() public {
        initializeV2();
        vm.warp(block.timestamp + 7 days);
        vm.startPrank(address(1234), address(1234));
        arNXMVaultProxy.getRewardNxm();
        vm.expectRevert("reward interval not reached");
        arNXMVaultProxy.getRewardNxm();
        vm.stopPrank();
    }

    function testStakeNXM() public {
        initializeV2();
        // add nxm to nxmvault from nxm whale
        vm.startPrank(nxmWhale);
        nxm.transfer(address(arNXMVaultProxy), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint trancheId = 217;
        uint amountToStake = 1000e18;

        IStakingPool stakingPool = IStakingPool(riskPools[0]);

        (uint stakeSharesBefore, uint rewardSharesBefore) = stakingPool
            .getTranche(trancheId);

        uint vaultNXMBalBefore = nxm.balanceOf(address(arNXMVaultProxy));
        uint aumBefore = arNXMVaultProxy.aum();

        // deposit to staking pool
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[0]);

        uint vaultNXMBalAfter = nxm.balanceOf(address(arNXMVaultProxy));
        uint aumAfter = arNXMVaultProxy.aum();

        // aum increases by 1 uinits so >= is used instead of ==
        require(aumAfter >= aumBefore, "aum should not decrease");

        require(
            (vaultNXMBalBefore - vaultNXMBalAfter) == amountToStake,
            "nxm not staked"
        );

        (uint stakeSharesAfter, uint rewardSharesAfter) = stakingPool
            .getTranche(trancheId);

        // stake shares should increase
        require(
            stakeSharesAfter > stakeSharesBefore,
            "stake shares not updated"
        );
        // reward shares should increase
        require(
            rewardSharesAfter > rewardSharesBefore,
            "reward shares not updated"
        );
    }

    function testStakeNXMWithInvalidStakingPoolToken() public {
        initializeV2();
        // add nxm to nxmvault from nxm whale
        vm.startPrank(nxmWhale);
        nxm.transfer(address(arNXMVaultProxy), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint trancheId = 217;
        uint amountToStake = 1000e18;

        // deposit to staking pool
        vm.expectRevert(InvalidStakingPoolForToken.selector);

        // stake with invalid staking pool for token
        stakeNxm(amountToStake, riskPools[0], trancheId, tokenIds[1]);
    }

    function testStakeNXMAndGetNewNFT() public {
        initializeV2();
        // add nxm to nxmvault from nxm whale
        vm.startPrank(nxmWhale);
        nxm.transfer(address(arNXMVaultProxy), 10000e18);
        vm.stopPrank();
        // first active tranche Id
        uint trancheId = 217;
        uint amountToStake = 1000e18;
        uint stakingNFTBalBefore = stakingNFT.balanceOf(
            address(arNXMVaultProxy)
        );

        uint aumBefore = arNXMVaultProxy.aum();
        // array should only have 2 elements
        vm.expectRevert();
        arNXMVaultProxy.tokenIds(2);

        // deposit to staking pool and get new nft (*0 as tokenID mints new one)
        stakeNxm(amountToStake, riskPools[0], trancheId, 0);

        uint aumAfter = arNXMVaultProxy.aum();

        uint stakingNFTBalAfter = stakingNFT.balanceOf(
            address(arNXMVaultProxy)
        );

        // should mint new nft
        require(
            (stakingNFTBalAfter - stakingNFTBalBefore) == 1,
            "nft not minted"
        );
        uint mintedNFTTokenId = stakingNFT.totalSupply();
        require(
            stakingNFT.ownerOf(mintedNFTTokenId) == address(arNXMVaultProxy),
            "arNXM vault should be owner of new nft"
        );

        INFTDescriptor nftDescriptor = INFTDescriptor(
            stakingNFT.nftDescriptor()
        );

        (, uint actualStaked, ) = nftDescriptor.getActiveDeposits(
            mintedNFTTokenId,
            riskPools[0]
        );
        // total staked returned by nexus is little bit less than actual staked
        require(actualStaked >= (amountToStake - 1e12), "wrong total staked");

        // aum should be equal to or greater than actual staked
        require(aumAfter >= aumBefore, "aum should be >= aum before");

        // check if new tokenId was added to tokenIds array
        uint newTokenId = arNXMVaultProxy.tokenIds(2);
        require(newTokenId == mintedNFTTokenId, "wrong token id");

        // check if new token id was mapped to risk pool
        address stakedRiskPool = arNXMVaultProxy.tokenIdToPool(newTokenId);
        require(stakedRiskPool == riskPools[0], "wrong risk pool");
    }

    function testUnstakeNXM() public {
        initializeV2();
        uint trancheId = 213;
        uint[] memory trancheIds = new uint[](1);
        // approximation
        uint expectedUnstakeAmount = 17000e18;
        trancheIds[0] = trancheId;
        uint vaultNXMBalBefore = nxm.balanceOf(address(arNXMVaultProxy));
        vm.warp(block.timestamp + 92 days);
        unstakeNxm(tokenIds[0], trancheIds);
        uint vaultNXMBalAfter = nxm.balanceOf(address(arNXMVaultProxy));
        require(
            vaultNXMBalAfter > (vaultNXMBalBefore + expectedUnstakeAmount),
            "nxm transfer failed"
        );
    }

    function testUnstakeNXMFail() public {
        initializeV2();
        uint trancheId = 213;
        uint[] memory trancheIds = new uint[](1);
        trancheIds[0] = trancheId;
        uint vaultNXMBalBefore = nxm.balanceOf(address(arNXMVaultProxy));
        unstakeNxm(tokenIds[0], trancheIds);
        uint vaultNXMBalAfter = nxm.balanceOf(address(arNXMVaultProxy));

        // as tranche has not expired it should not unstake 0 NXM
        require(vaultNXMBalAfter == vaultNXMBalBefore, "should not unstake");
    }

    function testWithdrawNxmFromPool() public {
        initializeV2();
        uint trancheId = 213;
        uint[] memory trancheIds = new uint[](1);
        // approx unstake amount
        uint expectedUnstakeAmount = 17000e18;
        trancheIds[0] = trancheId;
        uint vaultNXMBalBefore = nxm.balanceOf(address(arNXMVaultProxy));
        vm.warp(block.timestamp + 92 days);
        vm.startPrank(multisig);
        arNXMVaultProxy.withdrawNxm(riskPools[0], tokenIds[0], trancheIds);
        vm.stopPrank();
        uint vaultNXMBalAfter = nxm.balanceOf(address(arNXMVaultProxy));

        require(
            vaultNXMBalAfter > (vaultNXMBalBefore + expectedUnstakeAmount),
            "nxm transfer failed"
        );
    }

    function testRemoveTokenId() public {
        initializeV2();
        // index 1 means we have 2 tokenIds
        uint tokenIdAtIndex0Before = arNXMVaultProxy.tokenIds(0);

        require(tokenIdAtIndex0Before == tokenIds[0], "wrong token id");

        // as tokenIds length is 2 this should not revert
        arNXMVaultProxy.tokenIds(1);

        address riskPoolBefore = arNXMVaultProxy.tokenIdToPool(
            tokenIdAtIndex0Before
        );

        // remove one of tokenIds
        vm.startPrank(multisig);
        arNXMVaultProxy.removeTokenIdAtIndex(0);
        vm.stopPrank();

        // as tokenIds length is 1 this should revert
        vm.expectRevert();
        arNXMVaultProxy.tokenIds(1);

        address riskPoolAfter = arNXMVaultProxy.tokenIdToPool(
            tokenIdAtIndex0Before
        );

        require(riskPoolBefore != riskPoolAfter, "wrong risk pool");
        require(riskPoolAfter == address(0), "risk pool should be 0x0");
        uint tokenIdAtIndex0After = arNXMVaultProxy.tokenIds(0);

        require(
            tokenIdAtIndex0After != tokenIdAtIndex0Before,
            "token id at index should change"
        );
    }
}
