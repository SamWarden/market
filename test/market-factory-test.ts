import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract } from "ethers";
import chai from "chai";
// import chaiAsPromised from "chai-as-promised";
import { solidity } from "ethereum-waffle";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import type {
  MarketFactory__factory,
  Market__factory,
  TToken__factory,
  ConditionalToken__factory,
} from "../typechain";

// chai.use(chaiAsPromised);
chai.use(solidity);
const { expect } = chai;

interface Event extends Log{
  event: string;
  args: Array<any>;
}

interface TransactionReceiptWithEvents extends TransactionReceipt{
  events?: Array<Event>;
}
function function_name(argument: Contract) {
  // body...
}
describe("MarketFactory", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];
  let MarketFactory: MarketFactory__factory;
  let Market: Market__factory;
  let TToken: TToken__factory;
  let ConditionalToken: ConditionalToken__factory;

  beforeEach(async () => {
    // Get factories of contracts
    MarketFactory = await ethers.getContractFactory("MarketFactory") as MarketFactory__factory;
    Market = await ethers.getContractFactory("Market") as Market__factory;
    TToken = await ethers.getContractFactory("TToken") as TToken__factory;
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;

    // Get list of signers
    accounts = await ethers.getSigners();
  });

  it("test_deploy", async () => {

    // Get account what will call methods
    const signer: SignerWithAddress = accounts[0];

    // Set balance of collateral token for initial liquidity and freezed tokens
    const collateralBalance: string = "100000";
    // Set the duration of a market
    const duration: number = 10000;

    // Deploy DAI contract
    const dai = await TToken.deploy("DAI", "DAI", 18);
    await dai.deployed();

    // Deploy the MarketFactory contract
    const marketFactory = await MarketFactory.deploy(dai.address);
    await marketFactory.deployed();
    // Load contract of baseMarket
    const market = Market.attach(await marketFactory.baseMarket());

    // Listen events from LOG_CALL
    // market.on(await market.filters.LOG_CALL(), (res) => {console.log(res)});

    // Mint tokens to the account
    await dai.mint(signer.address, ethers.utils.parseEther(collateralBalance));
    // Approve collateral balance to the factory
    await dai.approve(marketFactory.address, ethers.utils.parseEther(collateralBalance));

    // Log addresses
    console.log("Signer_address: " + signer.address);
    console.log("MarketFactory_address: " + marketFactory.address);
    console.log("Market_address: " + market.address);

    // Create market
    let createResult: TransactionResponse = await marketFactory.create("DAI", "ETH/USD", duration, ethers.utils.parseEther(collateralBalance));
    expect(createResult).to.emit(marketFactory, 'Created').withArgs(address, "ETH/USD", "DAI", now, duration);
    // let txReceipt: TransactionReceiptWithEvents = await tx.wait();
    // if (txReceipt.events === undefined) {
    //   throw Error("There isn't `events` in the `txReceipt`");
    // }

    // for (let event of txReceipt.events.filter((event: Event) => event.event == "Created")) {
    //   console.log(event.args);
    // }
  });
});
