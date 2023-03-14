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
    uint forkBeforePause;
    uint currentFork;
    uint forkBeforeDump;

    IarNXMVault arNXMVaultProxy;
    IERC20 nxm = IERC20(0xd7c49CEE7E9188cCa6AD8FF264C1DA2e69D4Cf3B);
    IERC20 wNXM = IERC20(0x0d438F3b5175Bebc262bF23753C1E53d03432bDE);

    address stakingNFT = 0xcafea508a477D94c502c253A58239fb8F948e97f;
    address implAddress;
    address[] riskPools = [
        0x462340b61e2ae2C13f01F66B727d1bFDc907E53e,
        0xed9915e07aF860C3263801E223C9EaB512EB7C09
    ];
    uint[] tokenIds = [3, 4];

    address multisig = 0x1f28eD9D4792a567DaD779235c2b766Ab84D8E33;

    function setUp() public {
        arNXMVaultProxy = IarNXMVault(
            0x1337DEF1FC06783D4b03CB8C1Bf3EBf7D0593FC4
        );
        currentFork = vm.createFork(
            "https://mainnet.infura.io/v3/0c7537c516c74815abb1b4d3ad076a2e"
        );

        forkBeforeDump = vm.createFork(
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
        arNXMVaultProxy.initializeV2(
            IStakingNFT(stakingNFT),
            tokenIds,
            riskPools
        );

        vm.stopPrank();
    }

    function testImplementation() public {
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
            arNXMVaultProxy.stakingNFT() == stakingNFT,
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

    function testReward() public {
        initializeV2();
        // @todo test rewards here
    }

    function testDeposit() public {
        initializeV2();
        // @todo prank as a wNXM whale
    }

    function testWithdraw() public {
        initializeV2();
        // @todo withdraw from the vault
    }

    function testFinalizeWithdrawal() public {
        initializeV2();
        // @todo finalize withdrawal
    }
}
