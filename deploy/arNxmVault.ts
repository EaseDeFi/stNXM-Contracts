/*import "@nomiclabs/hardhat-ethers";
import hre, { ethers } from "hardhat";
import "hardhat-deploy";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployArNxmImpl: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const {
    getNamedAccounts,
    deployments: { deploy },
  } = hre;
  const { deployer1 } = await getNamedAccounts();
  console.log(hre.network.name);

  // fund deployer
  if (hre.network.name === "tenderly") {
    await hre.network.provider.send("tenderly_setBalance", [
      [deployer1],
      //amount in wei will be set for all wallets
      ethers.utils.hexValue(
        ethers.utils.parseUnits("1000", "ether").toHexString()
      ),
    ]);
  }

  if (hre.network.name === "hardhat") {
    // fund the  deployer
    await hre.network.provider.send("hardhat_setBalance", [
      deployer1,
      "0x3635c9adc5dea00000", // 1000 ETH
    ]);
  }

  console.log(
    `Balance of deployer1 : ${await ethers.provider.getBalance(
      deployer1
    )} ${deployer1}`
  );

  const gasPrice = (await ethers.provider.getFeeData()).gasPrice
    ?.mul(110)
    .div(100);

  const arNXMVault = await deploy("arNXMVault", {
    args: [],
    from: deployer1,
    log: true,
    gasPrice: gasPrice,
  });

  console.log(`arNXMVault deployed to ${arNXMVault.address}`);

  if (["mainnet", "goerli"].includes(hre.network.name)) {
    // verify etherscan
    console.log(`Verifying arNXMVault...`);
    try {
      await hre.run("verify:verify", {
        address: arNXMVault.address,
        constructorArguments: [],
      });
      console.log(`arNXMVault contract verified!`);
    } catch {
      console.log("Couldn't verify arNXMVault contract!");
    }
  }
};

export default deployArNxmImpl;

if (typeof require !== "undefined" && require.main === module) {
  deployArNxmImpl(hre);
}
*/