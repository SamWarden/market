import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import { expect } from "chai";

describe("Market", async () => {
  console.log("start");
  let accounts: Signer[];

  beforeEach(async () => {
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async () => {
    const Market: ContractFactory = await ethers.getContractFactory("Market");
    const market: Contract = await Market.deploy();

    console.log(market.address);
    console.log(market.deployTransaction.hash);

    await market.deplyed();

    console.log(await market.getStage());
    expect(await market.getStage()).to.equal("Created");
  });
});
