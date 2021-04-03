import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import { expect } from "chai";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("MarketFactory", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];

  beforeEach(async () => {
    // Get list of signers
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async () => {
    // Get factories of contracts
    const MarketFactory: ContractFactory = await ethers.getContractFactory("MarketFactory");
    const Market: ContractFactory = await ethers.getContractFactory("Market");
    const TToken: ContractFactory = await ethers.getContractFactory("TToken");

    // Get account what will call methods
    const signer: SignerWithAddress = accounts[0];

    // Set balance of collateral token for initial liquidity and freezed tokens
    const collateralBalance: string = "100000";
    // Set the duration of a market
    const duration: number = 10000;

    // Deploy DAI contract
    const dai: Contract = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();

    // Deploy the MarketFactory contract
    const marketFactory: Contract = await MarketFactory.deploy(dai.address);
    await marketFactory.deployed();
    // Load contract of baseMarket
    const market: Contract = Market.attach(await marketFactory.baseMarket());
    // Listen events from LOG_CALL
    market.on(await market.filters.LOG_CALL(), (res) => {console.log(res)});

    // Mint tokens to the account
    await dai.mint(signer.address, ethers.utils.parseEther(collateralBalance));
    // Approve collateral balance to the factory
    await dai.approve(marketFactory.address, ethers.utils.parseEther(collateralBalance));

    // Log addresses
    console.log("Signer_address: " + signer.address);
    console.log("MarketFactory_address: " + marketFactory.address);
    console.log("MarketFactory_hash: " + marketFactory.deployTransaction.hash);
    console.log("Market_address: " + market.address);
    console.log("Market_owner: " + await market.owner());

    // Create market
    await marketFactory.create("DAI", "ETH/USD", duration, ethers.utils.parseEther(collateralBalance));
  });
});
