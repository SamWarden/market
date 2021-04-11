import { ethers } from "hardhat";
import { Signer, Contract, BigNumber } from "ethers";
import chai from "chai";
// import chaiAsPromised from "chai-as-promised";
import { solidity } from "ethereum-waffle";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import type { TransactionReceiptWithEvents } from "../src/types";
import type {
  MarketFactory__factory, MarketFactory as MarketFactoryCreate,
  TClones__factory, TClones as TClonesContract,
  Market__factory, Market as MarketContract,
  TToken__factory, TToken as TTokenContract,
  ConditionalToken__factory, ConditionalToken as ConditionalTokenContract,
} from "../typechain";

// chai.use(chaiAsPromised);
chai.use(solidity);
const { expect } = chai;


describe("MarketFactory", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];
  let MarketFactory: MarketFactory__factory;
  let Market: Market__factory;
  let TToken: TToken__factory;
  let ConditionalToken: ConditionalToken__factory;
  let owner: SignerWithAddress;
  let account: SignerWithAddress;
  let dai: TTokenContract;
  let baseMarket: MarketContract;
  let baseConditionalToken: ConditionalTokenContract;
  const collateralBalance: BigNumber = ethers.utils.parseEther("100000");
  const duration: number = 10000;
  const collateralName: string = "DAI";
  const currencyPair: string = "ETH/USD";
  const protocolFee: BigNumber = ethers.utils.parseEther("0.3");

  before(async () => {
    // Get factories of contracts
    MarketFactory = await ethers.getContractFactory("MarketFactory") as MarketFactory__factory;
    Market = await ethers.getContractFactory("Market") as Market__factory;
    TToken = await ethers.getContractFactory("TToken") as TToken__factory;
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;

    baseMarket = await Market.deploy();
    await baseMarket.deployed();
    baseConditionalToken = await ConditionalToken.deploy();
    await baseConditionalToken.deployed();
  });

  beforeEach(async () => {
    // Deploy DAI contract
    dai = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();

    // Get list of signers
    accounts = await ethers.getSigners();
    owner = accounts[0];
    account = accounts[1];
  });

  it("test_deploy", async () => {
    // Deploy the MarketFactory contract
    const marketFactory: MarketFactoryCreate = await MarketFactory.deploy(baseMarket.address, baseConditionalToken.address, dai.address);
    await marketFactory.deployed();
  });

  describe("deployed", async () => {
    let marketFactory: MarketFactoryCreate;
    let accMarketFactory: MarketFactoryCreate;

    beforeEach(async () => {
      // Deploy the MarketFactory contract
      marketFactory = await MarketFactory.deploy(baseMarket.address, baseConditionalToken.address, dai.address);
      await marketFactory.deployed();
      accMarketFactory = marketFactory.connect(account);
    });

    it("test_create", async () => {
      // Mint tokens to the account
      await dai.mint(owner.address, collateralBalance);
      // Approve collateral balance to the factory
      await dai.approve(marketFactory.address, collateralBalance);
      console.log(await dai.allowance(owner.address, marketFactory.address), await dai.allowance(owner.address, marketFactory.address) == collateralBalance);
      // Create market
      expect(await marketFactory.create(collateralName, currencyPair, duration, collateralBalance)).to.emit(marketFactory, "Created");
      // await expect(accMarketFactory.create(collateralName, currencyPair, duration, collateralBalance)).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(marketFactory.create("None", currencyPair, duration, collateralBalance)).to.be.revertedWith("Invalid colleteral currency");
      await expect(marketFactory.create(collateralName, "None/None", duration, collateralBalance)).to.be.revertedWith("Invalid currency pair");
      await expect(marketFactory.create(collateralName, currencyPair, 1, collateralBalance)).to.be.revertedWith("Invalid duration");
    });

    describe("create_market", async () => {
      let market: MarketContract;

      beforeEach(async () => {
        // Mint tokens to the account
        await dai.mint(owner.address, collateralBalance);
        // Approve collateral balance to the factory
        await dai.approve(marketFactory.address, collateralBalance);
        console.log(await dai.allowance(owner.address, marketFactory.address), await dai.allowance(owner.address, marketFactory.address) == collateralBalance);
        // Create market
        const tx = await marketFactory.create(collateralName, currencyPair, duration, collateralBalance);

        expect(tx).to.emit(marketFactory, "Created");
        //TransactionReceiptWithEvents
        const txReceipt = await tx.wait();
        market = Market.attach(txReceipt.events![txReceipt.events!.length - 1].args![0]);
        console.log(await market.bull());
      });

      it("test_market_check", async () => {
        expect(await marketFactory.isMarket(market.address)).to.be.true;
      });
    });
        // .withArgs(address, "ETH/USD", "DAI", now, duration);
      // let txReceipt: TransactionReceiptWithEvents = await tx.wait();
      // if (txReceipt.events === undefined) {
      //   throw Error("There isn't `events` in the `txReceipt`");
      // }

      // for (let event of txReceipt.events.filter((event: Event) => event.event == "Created")) {
      //   console.log(event.args);
      // }
    // });

    it("test_protocol_fee", async () => {
      expect(await marketFactory.protocolFee()).to.equal(0);
      expect(await marketFactory.setProtocolFee(protocolFee));
      expect(await marketFactory.protocolFee()).to.equal(protocolFee);
      await expect(accMarketFactory.setProtocolFee(protocolFee)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("test_swap_fee", async () => {
      const swapFee: BigNumber = ethers.utils.parseEther("1").div(1000).mul(3);
      // expect(await marketFactory.swapFee()).to.equal(ethers.utils.parseEther("0.3"));
      expect(await marketFactory.setSwapFee(swapFee));
      expect(await marketFactory.swapFee()).to.equal(swapFee);
      await expect(accMarketFactory.setSwapFee(swapFee)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("test_collect", async () => {
      const collectAmount: BigNumber = ethers.utils.parseEther("1");
      await dai.mint(owner.address, collectAmount);
      await dai.transfer(marketFactory.address, collectAmount);
      expect(await marketFactory.collect(dai.address));
      expect(await dai.balanceOf(owner.address)).to.equal(collectAmount);
      await expect(accMarketFactory.collect(dai.address)).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });
});
// const MarketFactory = await ethers.getContractFactory("MarketFactory");
// const Market = await ethers.getContractFactory("Market");
// const TToken = await ethers.getContractFactory("TToken");
// const a = ethers.getSigner();
// const collateralBalance = "100000";
// const duration = 10000;
// const dai = await TToken.deploy("DAI", "DAI", 18);
// await dai.deployed();
// let marketFactory = await MarketFactory.deploy(dai.address);
// await marketFactory.deployed();
// let market = Market.attach(await marketFactory.baseMarket());
// await dai.mint(a.address, ethers.utils.parseEther(collateralBalance).mul(100));
// await dai.approve(marketFactory.address, ethers.utils.parseEther(collateralBalance).mul(100));
// await marketFactory.create("DAI", "ETH/USD", duration, ethers.utils.parseEther(collateralBalance));
