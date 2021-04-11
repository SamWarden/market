import type { TransactionResponse, TransactionReceipt, Log } from "@ethersproject/abstract-provider";
import type {
  TClones__factory, TClones as TClonesContract,
  Market__factory, Market as MarketContract,
  TToken__factory, TToken as TTokenContract,
  ConditionalToken__factory, ConditionalToken as ConditionalTokenContract,
} from "../typechain/";


export interface Event extends Log {
  event: string;
  args: Array<any>;
}

export interface TransactionReceiptWithEvents extends TransactionReceipt {
  events?: Array<Event>;
}

export interface ContractFactory<ContractType> {
  attach(address: string): ContractType;
  deploy(...args: any[]): ContractType;
}

export {TClonesContract, TransactionReceipt, TransactionResponse};
