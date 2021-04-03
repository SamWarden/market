import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import { expect } from "chai";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("Market", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];

  beforeEach(async () => {
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async () => {
    const Market: ContractFactory = await ethers.getContractFactory("Market");
    const market: Contract = await Market.deploy();

    console.log(market.address);
    console.log(market.deployTransaction.hash);

    await market.deployed();

    console.log(await market.getStage());
    expect(await market.getStage()).to.eq(0);
  });
});
