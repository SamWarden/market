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
  let accDai: TTokenContract;
  const collateralBalance: BigNumber = ethers.utils.parseEther("100000");
  const duration: number = 10000;
  const collateralName: string = "DAI";
  const baseCurrency: string = "ETH";
  const protocolFee: BigNumber = ethers.utils.parseEther("0.003");
  const initialPrice: BigNumber = ethers.utils.parseEther("10000");
  let TClones: TClones__factory;
  let tclones: TClonesContract;

  before(async () => {
    // Get list of signers
    accounts = await ethers.getSigners();
    owner = accounts[0];
    account = accounts[1];

    // Get factories of contracts
    Market = await ethers.getContractFactory("Market") as Market__factory;
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;
    TToken = await ethers.getContractFactory("TToken") as TToken__factory;
    TClones = await ethers.getContractFactory("TClones") as TClones__factory;
    tclones = await TClones.deploy();
    await tclones.deployed();
  });

  beforeEach(async () => {
    // Deploy DAI contract
    dai = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();

    accDai = dai.connect(account);
  });

  it("events_signature", async () => {
    expect(Market.interface.events).to.include.all.keys(
      "Approval(address,address,uint256)",
      "Transfer(address,address,uint256)",
      "LOG_CALL(bytes4,address,bytes)",
      "LOG_EXIT(address,address,uint256)",
      "LOG_JOIN(address,address,uint256)",
      "LOG_SWAP(address,address,address,uint256,uint256)",
      "Buy(address,uint256,uint256)",
      "Closed(uint256,int256,uint8,address)",
      "Open(uint256,int256)",
      "Redeem(address,uint256,uint256)",
      // "Created(string,string,uint8,uint256)",
    );
  });

  it("deploy", async () => {
    const market = await Market.deploy();
    await market.deployed();
  });

  describe("deployed", async () => {
    let market: MarketContract;
    let accMarket: MarketContract;
    let bull: ConditionalTokenContract;
    let bear: ConditionalTokenContract;
    let accBull: ConditionalTokenContract;
    let accBear: ConditionalTokenContract;

    beforeEach(async () => {
      market = await Market.deploy();
      bull = await ConditionalToken.deploy();
      bear = await ConditionalToken.deploy();

      await market.deployed();
      await bull.deployed();
      await bear.deployed();
    });

    it("deployed_stage", async () => {
      expect(await market.stage()).to.equal(1); //Stages.Base
    });

    it("call_clone_constructor", async () => {
      await expect(market.cloneConstructor(dai.address, bull.address, bear.address, duration, baseCurrency, collateralName, protocolFee))
        .to.be.revertedWith("Market: this Market is already initialized");
      market = await cloneContract(market.address, Market, tclones);
      expect(await market.stage()).to.equal(0); //Stages.None
      await market.cloneConstructor(dai.address, bull.address, bear.address, duration, baseCurrency, collateralName, protocolFee);
    });
      // Listen events from LOG_CALL
      // market.on(await market.filters.LOG_CALL(), (res) => {console.log(res)});

      // Mint tokens to the account

    it("buy_before_init", async () => {
      await expect(market.buy(collateralBalance)).to.be.revertedWith("Market: this market is not open");
    });

    describe("initialized", async () => {
      const boughtTokens: BigNumber = ethers.utils.parseEther("100");

      beforeEach(async () => {
        market = await cloneContract(market.address, Market, tclones);
        bull = await cloneContract(bull.address, ConditionalToken, tclones);
        bear = await cloneContract(bear.address, ConditionalToken, tclones);

        accBull = bull.connect(account);
        accBear = bear.connect(account);
        accMarket = market.connect(account);

        await market.cloneConstructor(dai.address, bull.address, bear.address, duration, baseCurrency, collateralName, protocolFee);
        await bull.cloneConstructor("Bull", "Bull", 18);
        await bear.cloneConstructor("Bear", "Bear", 18);

        await dai.mint(owner.address, collateralBalance);
        await dai.approve(market.address, collateralBalance);

        await dai.mint(account.address, collateralBalance);
        await accDai.approve(market.address, collateralBalance);

        // await bull.mint(owner.address, collateralBalance);
        // await bull.approve(market.address, collateralBalance);

        // await bear.mint(owner.address, collateralBalance);
        // await bear.approve(market.address, collateralBalance);

        await bull.transferOwnership(market.address);
        await bear.transferOwnership(market.address);
      });

      it("initialized_result", async () => {
        expect(await market.result()).to.equal(0); //Results.Unknown
      });

      it("initialized_stage", async () => {
        expect(await market.stage()).to.equal(2); //Stages.Initialized
      });

      it("initialized_attributes", async () => {
        expect(await market.collateralToken()).to.equal(dai.address);
        expect(await market.bullToken()).to.equal(bull.address);
        expect(await market.bearToken()).to.equal(bear.address);
        expect(await market.duration()).to.equal(duration);
        expect(await market.baseCurrency()).to.equal(baseCurrency);
        expect(await market.collateralCurrency()).to.equal(collateralName);
        expect(await market.protocolFee()).to.equal(protocolFee);
      });

      it("buy_after_init", async () => {
        expect(await market.buy(collateralBalance)).to.emit(market, "Buy");
        expect(await bull.balanceOf(owner.address)).to.equal(collateralBalance);
        expect(await bear.balanceOf(owner.address)).to.equal(collateralBalance);
        expect(await dai.balanceOf(owner.address)).to.equal(0);
        await expect(accMarket.buy(collateralBalance)).to.be.revertedWith("Market: this market is not open");
      });

      it("_close_before_open", async () => {
        await expect(market._close(initialPrice)).to.be.revertedWith("Market: this market is not open");
      });

      it("open", async () => {
        expect(await market.open(initialPrice)).to.emit(market, "Open");
      });

      describe("open", async () => {
        beforeEach(async () => {
          await market.open(initialPrice);
        });

        it("reopen", async () => {
          await expect(market.open(initialPrice)).to.be.revertedWith("Market: this market is not initialized");
        });

        it("initial_price", async () => {
          expect(await market.initialPrice()).to.equal(initialPrice);
        });

        it("open_stage", async () => {
          expect(await market.stage()).to.equal(3); //Stages.Open
        });

        it("total_deposit_before_buy", async () => {
          expect(await market.totalDeposit()).to.equal(0);
        });

        it("buy_after_open", async () => {
          expect(await accMarket.buy(collateralBalance)).to.emit(market, "Buy");
          expect(await bull.balanceOf(account.address)).to.equal(collateralBalance);
          expect(await bear.balanceOf(account.address)).to.equal(collateralBalance);
          expect(await dai.balanceOf(account.address)).to.equal(0);
          await expect(market.buy(0)).to.be.revertedWith("Market: amount has to be greater than 0");
        });

        it("redeem_before_close", async () => {
          await expect(market.redeem(collateralBalance)).to.be.revertedWith("Market: this market is not closed");
        });

        describe("bought", async () => {
          beforeEach(async () => {
            await dai.burn(collateralBalance);
            await accMarket.buy(collateralBalance);
            await accBull.approve(market.address, collateralBalance);
            await accBear.approve(market.address, collateralBalance);
          });

          it("total_deposit_after_buy", async () => {
            expect(await market.totalDeposit()).to.equal(collateralBalance);
          });

          it("total_redemption_before_close", async () => {
            expect(await market.totalRedemption()).to.equal(0);
          });

          it("_close_draw", async () => {
            await expect(accMarket._close(initialPrice)).to.be.revertedWith("BPool: caller is not the owner");
            expect(await market._close(initialPrice)).to.emit(market, "Closed");
            expect(await market.stage()).to.equal(4); //Stages.Closed
            expect(await market.result()).to.equal(1); //Results.Draw
            await expect(market.buy(collateralBalance)).to.be.revertedWith("Market: this market is not open");
            expect(await accMarket.redeem(collateralBalance.mul(2))).to.emit(market, "Redeem");
            expect(await accBull.balanceOf(account.address)).to.equal(0);
            expect(await accBear.balanceOf(account.address)).to.equal(0);
            const fee: BigNumber = BigNumber.from("300000000000000000000");
            expect(await accDai.balanceOf(account.address)).to.equal(collateralBalance.sub(fee));
            expect(await dai.balanceOf(owner.address)).to.equal(fee);

            expect(await market.totalRedemption()).to.equal(collateralBalance);
          });

          it("_close_bull", async () => {
            await expect(market._close(initialPrice.add(1))).to.emit(market, "Closed");
            expect(await market.result()).to.equal(2); //Results.Bull
          });

          it("_close_bear", async () => {
            expect(await market._close(initialPrice.sub(1))).to.emit(market, "Closed");
            expect(await market.result()).to.equal(3); //Results.Bear
          });
        });
      });
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
