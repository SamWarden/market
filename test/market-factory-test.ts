import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import { expect } from "chai";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("MarketFactory", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];

  beforeEach(async () => {
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async () => {
    const MarketFactory: ContractFactory = await ethers.getContractFactory("MarketFactory");
    const TToken: ContractFactory = await ethers.getContractFactory("TToken");
    const signer: SignerWithAddress = accounts[0];
    const collateralBalance = "100000";

    const dai: Contract = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();
    await dai.mint(signer.address, ethers.utils.parseEther(collateralBalance));

    const marketFactory: Contract = await MarketFactory.deploy(dai.address);

    console.log(marketFactory.address);
    console.log(marketFactory.deployTransaction.hash);

    await marketFactory.deployed();

    //console.log(await marketFactory.getStage());
    //expect(await marketFactory.getStage()).to.equal("Created");
  });
});
