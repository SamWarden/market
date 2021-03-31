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
  const Market: ContractFactory = await ethers.getContractFactory("Market");
  await deploy_contract(Market);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
