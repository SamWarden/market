import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import { expect } from "chai";

describe("Market", async function () {
  let accounts: Signer[];
  const Market: ContractFactory = await ethers.getContractFactory("Market");

  beforeEach(async function () {
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async function () {
    const market: Contract = await Market.deploy();

    console.log(market.address);
    console.log(market.deployTransaction.hash);

    await market.deplyed();

    console.log(await market.getStage());
    expect(await market.getStage()).to.equal("Created");
  });
});