import { ethers } from "hardhat";
import { Signer, Contract, BigNumber } from "ethers";
import chai from "chai";
// import chaiAsPromised from "chai-as-promised";
import { AddressZero } from "@ethersproject/constants";
import { solidity } from "ethereum-waffle";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import { cloneContract } from "../src/clones";
import type {
  TClones__factory, TClones as TClonesContract,
  Market__factory, Market as MarketContract,
  TToken__factory, TToken as TTokenContract,
  ConditionalToken__factory, ConditionalToken as ConditionalTokenContract,
} from "../typechain";

// chai.use(chaiAsPromised);
chai.use(solidity);
const { expect } = chai;

describe("Market", async () => {
  let accounts: SignerWithAddress[];
  let owner: SignerWithAddress;
  let account: SignerWithAddress;
  let Market: Market__factory;
  let TToken: TToken__factory;
  let ConditionalToken: ConditionalToken__factory;
  let dai: TTokenContract;
  const collateralBalance: BigNumber = ethers.utils.parseEther("100000");
  const duration: number = 10000;
  const collateralName: string = "DAI";
  const currencyPair: string = "USD/ETH";
  const protocolFee: BigNumber = ethers.utils.parseEther("0.3");
  let TClones: TClones__factory;
  let tclones: TClonesContract;

  before(async () => {
    // Get factories of contracts
    Market = await ethers.getContractFactory("Market") as Market__factory;
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;
    TToken = await ethers.getContractFactory("TToken") as TToken__factory;
    TClones = await ethers.getContractFactory("TClones") as TClones__factory;
    tclones = await TClones.deploy();
    await tclones.deployed();
  });

  beforeEach(async () => {
    // Get list of signers
   
    accounts = await ethers.getSigners();
    owner = accounts[0];
    account = accounts[1];

    // Deploy DAI contract
    dai = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();
  });

  it("test_events_signature", async () => {
    expect(Market.interface.events).to.include.all.keys(
      "Approval(address,address,uint256)",
      "Transfer(address,address,uint256)",
      "LOG_CALL(bytes4,address,bytes)",
      "LOG_EXIT(address,address,uint256)",
      "LOG_JOIN(address,address,uint256)",
      "LOG_SWAP(address,address,address,uint256,uint256)",
      "Buy(uint256,uint256)",
      "Closed(uint256,int256,uint8,address)",
      "OwnershipTransferred(address,address)",
      "Redeem(uint256,uint256)",
      // "Created(string,string,uint8,uint256)",
    );
  });

  it("test_deploy", async () => {
    const market = await Market.deploy();
    await market.deployed();
  });

  describe("deployed", async () => {
    let market: MarketContract;
    let bull: ConditionalTokenContract;
    let bear: ConditionalTokenContract;

    beforeEach(async () => {
      market = await Market.deploy();
      bull = await ConditionalToken.deploy();
      bear = await ConditionalToken.deploy();

      await market.deployed();
      await bull.deployed();
      await bear.deployed();

      bull = await cloneContract(bull.address, ConditionalToken, tclones);
      bear = await cloneContract(bear.address, ConditionalToken, tclones);

      await bull.cloneConstructor("Bull", "Bull", 18);
      await bear.cloneConstructor("Bear", "Bear", 18);

      await dai.mint(owner.address, collateralBalance);
      await dai.approve(market.address, collateralBalance);

      await bull.mint(owner.address, collateralBalance);
      await bull.approve(market.address, collateralBalance);

      await bear.mint(owner.address, collateralBalance);
      await bear.approve(market.address, collateralBalance);
    });

    it("test_call_clone_constructor", async () => {
      console.log(market.address, dai.address, bear.address, bull.address);
      await market.cloneConstructor(dai.address, bull.address, bear.address, duration, collateralName, currencyPair, AddressZero, protocolFee);
      // await expect(market.cloneConstructor(dai.address, bull.address, bear.adderss, duration, collateralName, currencyPair, AddressZero, protocolFee))
        // .to.be.revertedWith("Market: This Market is already initialized");
      console.log('ji');
      market = await cloneContract(market.address, ConditionalToken, tclones);
      console.log(await market.stage());
      // expect(await market.cloneConstructor(dai.address));//, //bull.address, bear.adderss, duration, collateralName, currencyPair, AddressZero, protocolFee));
        // .to.emit(market, "Created");
      // Listen events from LOG_CALL
      // market.on(await market.filters.LOG_CALL(), (res) => {console.log(res)});

      // Mint tokens to the account

      // Log addresses
      console.log("Signer_address: " + owner.address);
      // console.log("MarketFactory_address: " + marketFactory.address);
      console.log("Market_address: " + market.address);
    });

    describe("Initialized", async () => {});
      beforeEach(async () => {
        market = await cloneContract(market.address, ConditionalToken, tclones);
        await market.cloneConstructor(dai.address, bull.address, bear.address, duration, collateralName, currencyPair, AddressZero, protocolFee);
      });

      it("test_open", async () => {
        //
      });  
      // Create market
      // let createResult: TransactionResponse = await marketFactory.create("DAI", "ETH/USD", duration, ethers.utils.parseEther(collateralBalance));
      // expect(createResult).to.emit(marketFactory, "Created");
        // .withArgs(address, "ETH/USD", "DAI", now, duration);
      // let txReceipt: TransactionReceiptWithEvents = await tx.wait();
      // if (txReceipt.events === undefined) {
      //   throw Error("There isn't `events` in the `txReceipt`");
      // }

      // for (let event of txReceipt.events.filter((event: Event) => event.event == "Created")) {
      //   console.log(event.args);
      // }
  });

});
