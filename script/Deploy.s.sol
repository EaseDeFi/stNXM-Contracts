// SPDX-License-Identifier: (c) Ease DAO
pragma solidity 0.8.20;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
//import {arNXMVault} from "contracts/core/arNXMVault.sol";

contract DeployVault is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        //address deployer = vm.addr(deployerPrivateKey);
        //arNXMVault arNXMVault = new arNXMVault();
        //console2.log("arNXMVault: ", address(arNXMVault));
        vm.stopBroadcast();
    }
}
