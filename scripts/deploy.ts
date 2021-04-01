import { ethers } from "hardhat";
import { ContractFactory, Contract } from "ethers";

async function deploy_contract(factory: ContractFactory): Promise<void> {
  let contract: Contract = await factory.deploy();

  console.log(contract.address);
  console.log(contract.deployTransaction.hash);
  //wait untill the contract will deploy
  await contract.deployed();
}

async function main(): Promise<void> {
  const MarketFactory: ContractFactory = await ethers.getContractFactory("MarketFactory");
  await deploy_contract(MarketFactory);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
