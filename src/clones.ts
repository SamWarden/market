import type { TransactionResponse, ContractFactory, TClonesContract, TransactionReceiptWithEvents } from "./types";


export async function cloneContract(address: string, contractFactory: ContractFactory<any>, tclones: TClonesContract) {
  const txResponse: TransactionResponse = await tclones.copy(address);
  const txResponseWithEvent: TransactionReceiptWithEvents = await txResponse.wait();
  const cloneAddress = txResponseWithEvent.events![0].args[0];
  const contract = contractFactory.attach(cloneAddress);
  return contract;
}
