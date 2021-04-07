import { ethers } from "hardhat";
import { Signer, ContractFactory, Contract, BigNumber } from "ethers";
import chai from "chai";
// import chaiAsPromised from "chai-as-promised";
import { AddressZero } from "@ethersproject/constants";
import { solidity } from "ethereum-waffle";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import type {
  ConditionalToken__factory, ConditionalToken as ConditionalTokenContract,
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

describe("ConditionalToken", async () => {
  console.log("start");
  let accounts: SignerWithAddress[];
  let owner: SignerWithAddress;
  let account: SignerWithAddress;
  let ConditionalToken: ConditionalToken__factory;

  before(async () => {
    // Get factories of contract
    ConditionalToken = await ethers.getContractFactory("ConditionalToken") as ConditionalToken__factory;
  });

  beforeEach(async () => {
    // Get list of signers
    accounts = await ethers.getSigners();
    owner = accounts[0];
    account = accounts[1];
  });

  it("test_events_signature", async () => {
    expect(ConditionalToken.interface.events).to.include.all.keys("Approval(address,address,uint256)", "Transfer(address,address,uint256)");
  });

  it("test_deploy", async () => {
    const token = await ConditionalToken.deploy();
    await token.deployed();
  });

  describe("deployed", async () => {
    let token: ConditionalTokenContract;
    let accToken: ConditionalTokenContract;
    beforeEach(async () => {
      token = await ConditionalToken.deploy();
      accToken = await token.connect(account);
      await token.deployed();
    });

    it("test_call_clone_constructor", async () => {
      expect(await token.cloneConstructor("Token", "TOK", 18)).to.emit(token, "Created");
      await expect(token.cloneConstructor("Token", "TOK", 18)).to.be.revertedWith("ConditionalToken: this token is already created");
    });
    
    describe("initialized", async () => {
      beforeEach(async () => {
        await token.cloneConstructor("Token", "TOK", 18);
      });

      it("test_get_name", async () => {
        expect(await token.name()).to.equal("Token");
      });

      it("test_get_symbol", async () => {
        expect(await token.symbol()).to.equal("TOK");
      });

      it("test_get_decimals", async () => {
        expect(await token.decimals()).to.equal(18);
      });

      it("test_get_owner", async () => {
        expect(await token.owner()).to.equal(owner.address);
      });

      it("test_get_total_supply", async () => {
        expect(await token.totalSupply()).to.equal(0);
      });

      it("test_balance_check", async () => {
        expect(await token.balanceOf(owner.address)).to.equal(0);
      });

      it("test_get_allowance", async () => {
        expect(await token.allowance(owner.address, account.address)).to.equal(0);
      });

      it("test_approve", async () => {
        const numberToAllowance: number = 1000;
        expect(await token.allowance(owner.address, account.address))
          .to.equal(0);
        expect(await token.approve(account.address, numberToAllowance))
          .to.emit(token, "Approval").withArgs(owner.address, account.address, numberToAllowance);
        expect(await token.allowance(owner.address, account.address))
          .to.equal(numberToAllowance);
      });

      it("test_mint", async () => {
        const numberToMint: number = 1000;
        expect(await token.balanceOf(owner.address)).to.equal(0);
        expect(await token.mint(owner.address, numberToMint)).to.emit(token, "Transfer").withArgs(AddressZero, owner.address, numberToMint);
        expect(await token.balanceOf(owner.address)).to.equal(numberToMint);
        expect(await token.totalSupply()).to.equal(numberToMint);

        await expect(token.mint(AddressZero, numberToMint)).to.be.revertedWith("ERC20: mint to the zero address");
        await expect(accToken.mint(owner.address, numberToMint)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("test_burn", async () => {
        const numberToBurn: number = 1000;
        expect(await token.mint(owner.address, numberToBurn)).to.emit(token, "Transfer").withArgs(AddressZero, owner.address, numberToBurn);
        expect(await token.balanceOf(owner.address)).to.equal(numberToBurn);
        expect(await token.totalSupply()).to.equal(numberToBurn);
        expect(await token.burn(numberToBurn)).to.emit(token, "Transfer").withArgs(owner.address, AddressZero, numberToBurn);
        expect(await token.balanceOf(owner.address)).to.equal(0);
        expect(await token.totalSupply()).to.equal(0);

        await expect(accToken.burn(numberToBurn)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("test_burn_from", async () => {
        const numberToBurn: number = 1000;
        await expect(token.burnFrom(account.address, numberToBurn))
          .to.be.revertedWith("ERC20: burn amount exceeds allowance");
        expect(await token.mint(account.address, numberToBurn))
          .to.emit(token, "Transfer").withArgs(AddressZero, account.address, numberToBurn);
        expect(await token.balanceOf(account.address)).to.equal(numberToBurn);
        expect(await accToken.approve(owner.address, numberToBurn))
          .to.emit(token, "Approval").withArgs(account.address, owner.address, numberToBurn);
        expect(await token.burnFrom(account.address, numberToBurn)).to.emit(token, "Transfer")
          .withArgs(account.address, AddressZero, numberToBurn);
        expect(await accToken.balanceOf(account.address)).to.equal(0);

        await expect(accToken.burnFrom(owner.address, numberToBurn)).to.be.revertedWith("Ownable: caller is not the owner");
      });

      it("test_transfer", async () => {
        const numberToTransfer: number = 1000;
        await expect(token.transfer(account.address, numberToTransfer))
          .to.be.revertedWith("ERC20: transfer amount exceeds balance");
        expect(await token.mint(owner.address, numberToTransfer))
          .to.emit(token, "Transfer").withArgs(AddressZero, owner.address, numberToTransfer);
        expect(await token.transfer(account.address, numberToTransfer))
          .to.emit(token, "Transfer").withArgs(owner.address, account.address, numberToTransfer);
        expect(await token.balanceOf(account.address)).to.equal(numberToTransfer);
      });

      it("test_transfer_from", async () => {
        const numberToTransfer: number = 1000;
        // Try to transferFrom without tokens
        await expect(token.transferFrom(account.address, owner.address, numberToTransfer))
          .to.be.revertedWith("ERC20: transfer amount exceeds balance");
        // Mint tokens
        expect(await token.mint(account.address, numberToTransfer))
          .to.emit(token, "Transfer").withArgs(AddressZero, account.address, numberToTransfer);

        // Try to transferFrom without allowance
        await expect(token.transferFrom(account.address, owner.address, numberToTransfer))
          .to.be.revertedWith("ERC20: transfer amount exceeds allowance"); 
        // To approve allowance
        expect(await accToken.approve(owner.address, numberToTransfer))
          .to.emit(token, "Approval").withArgs(account.address, owner.address, numberToTransfer);
        // Transfer tokens from account
        expect(await token.transferFrom(account.address, owner.address, numberToTransfer))
          .to.emit(token, "Transfer").withArgs(account.address, owner.address, numberToTransfer);
        // Balance changed
        expect(await token.balanceOf(owner.address)).to.equal(numberToTransfer);
        expect(await token.balanceOf(account.address)).to.equal(0);
        expect(await token.allowance(account.address, owner.address)).to.equal(0);
      });

    });
  });
});
