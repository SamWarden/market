import type { ContractFactory, TClonesContract } from "./types";


export async function cloneContract(address: string, contractFactory: ContractFactory<any>, tclones: TClonesContract) {
  await tclones.copy(address);
  const cloneAddress = await tclones.clone();
  const contract = contractFactory.attach(cloneAddress);
  return contract;
}
