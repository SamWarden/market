import { ethers } from "hardhat";
import { Signer, Contract, BigNumber } from "ethers";
import chai from "chai";
// import chaiAsPromised from "chai-as-promised";
import { solidity } from "ethereum-waffle";
import { AddressZero } from "@ethersproject/constants";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import type { TransactionReceiptWithEvents } from "../src/types";
import {
  MarketFactory__factory, MarketFactory as MarketFactoryContract,
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
  const conditionalBalance: BigNumber = collateralBalance.div(2);
  const duration: number = 1;
  const collateralName: string = "DAI";
  const currencyPair: string = "ETH/USD";
  const protocolFee: BigNumber = ethers.utils.parseEther("1").div(1000).mul(3);
  const swapFee: BigNumber = ethers.utils.parseEther("1").div(1000).mul(3);

  before(async () => {
    accounts = await ethers.getSigners();
    owner = accounts[0];
    account = accounts[1];

    // Get factories of contracts
    MarketFactory = await ethers.getContractFactory("MarketFactory") as MarketFactory__factory;
    Market = await ethers.getContractFactory("Market") as Market__factory;
    TToken = await ethers.getContractFactory("TToken") as TToken__factory;
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;
    // MarketFactory = new MarketFactory__factory(owner);
    // Market = new Market__factory(owner);
    // TToken = new TToken__factory(owner);
    // ConditionalToken = new ConditionalToken__factory(owner);

    baseMarket = await Market.deploy();
    await baseMarket.deployed();
    baseConditionalToken = await ConditionalToken.deploy();
    await baseConditionalToken.deployed();
  });

  beforeEach(async () => {
    // Deploy DAI contract
    dai = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();
  });

  it("test_deploy", async () => {
    // Deploy the MarketFactory contract
    const marketFactory: MarketFactoryContract = await MarketFactory.deploy(baseMarket.address, baseConditionalToken.address, dai.address);
    await marketFactory.deployed();
  });

  describe("deployed", async () => {
    let marketFactory: MarketFactoryContract;
    let accMarketFactory: MarketFactoryContract;

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
      // Create market
      const tx = await marketFactory.create(collateralName, currencyPair, duration, collateralBalance);
      expect(tx).to.emit(marketFactory, "Created");
      const txReceipt = await tx.wait();
      const market = Market.attach(txReceipt.events![txReceipt.events!.length - 1].args![0]);

      const bull = ConditionalToken.attach(await market.bullToken());
      const bear = ConditionalToken.attach(await market.bearToken());

      expect(await market.balanceOf(owner.address)).to.equal(await market.INIT_POOL_SUPPLY());
      expect(await bull.balanceOf(owner.address)).to.equal(conditionalBalance);
      expect(await bear.balanceOf(owner.address)).to.equal(conditionalBalance);

      // await expect(accMarketFactory.create(collateralName, currencyPair, duration, collateralBalance)).to.be.revertedWith("Ownable: caller is not the owner");
      await expect(marketFactory.create("None", currencyPair, duration, collateralBalance)).to.be.revertedWith("Invalid colleteral currency");
      await expect(marketFactory.create(collateralName, "None/None", duration, collateralBalance)).to.be.revertedWith("Invalid currency pair");
      // await expect(marketFactory.create(collateralName, currencyPair, 1, collateralBalance)).to.be.revertedWith("Invalid duration");
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

    describe("create_market", async () => {
      let market: MarketContract;
      let bull: ConditionalTokenContract;
      let bear: ConditionalTokenContract;

      beforeEach(async () => {
        // Mint tokens to the account
        await dai.mint(owner.address, collateralBalance);
        // Approve collateral balance to the factory
        await dai.approve(marketFactory.address, collateralBalance);

        await marketFactory.setSwapFee(swapFee);
        // Create market
        const tx = await marketFactory.create(collateralName, currencyPair, duration, collateralBalance);
        //TransactionReceiptWithEvents
        const txReceipt = await tx.wait();
        market = Market.attach(txReceipt.events![txReceipt.events!.length - 1].args![0]);
        console.log(await market.bullToken());

        bull = ConditionalToken.attach(await market.bullToken());
        bear = ConditionalToken.attach(await market.bearToken());

        // Mint tokens to the account
        await dai.mint(owner.address, collateralBalance);
        // Approve collateral balance to the market
        await dai.approve(market.address, collateralBalance);
      });

      it("test_market_check", async () => {
        expect(await marketFactory.isMarket(market.address)).to.be.true;
        expect(await marketFactory.isMarket(AddressZero)).to.be.false;
      });

      it("test_market_buy", async () => {
        expect(await bull.balanceOf(owner.address)).to.equal(conditionalBalance);
        expect(await market.buy(conditionalBalance)).to.emit(market, "Buy");
        expect(await bull.balanceOf(owner.address)).to.equal(conditionalBalance.mul(2));
      });

      // it("test_market_close", async () => {
      //   expect(await market.close(2)).to.emit(market, "Closed");
      //   await expect(market.buy(conditionalBalance)).to.be.revertedWith("Market: this market is not open");
      // });

      // it("test_market_redeem", async () => {
      //   await expect(market.redeem(conditionalBalance)).to.be.revertedWith("Market: this market is not closed");
      //   expect(await market.close(2)).to.emit(market, "Closed");
      //   await bull.approve(market.address, conditionalBalance);
      //   expect(await market.redeem(conditionalBalance)).to.emit(market, "Redeem");
      //   expect(await bull.balanceOf(owner.address)).to.equal(0);
      //   expect(await bear.balanceOf(owner.address)).to.equal(conditionalBalance);
      //   expect(await dai.balanceOf(owner.address)).to.equal(collateralBalance.add(conditionalBalance));
      // });

      it("test_market_spot_price", async () => {
        expect(await market.getSpotPrice(dai.address, bull.address)).to.equal(BigNumber.from("501504513540621866"));
      });

      it("test_market_spot_price_sans_fee", async () => {
        expect(await market.getSpotPriceSansFee(dai.address, bull.address)).to.equal(ethers.utils.parseEther("0.5"));
      });

      it("test_market_join_pool", async () => {
        console.log(await market.totalSupply());
        expect(await market.joinPool(10, [1, 1, 1]));
      });
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
