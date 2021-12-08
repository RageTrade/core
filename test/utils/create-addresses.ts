import { BigNumber } from '@ethersproject/bignumber';
import { hexDataSlice, keccak256, RLP, getAddress } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

export function getCreateAddress(deployerAddress: string, nonce: number): string {
  return getAddress(hexDataSlice(keccak256(RLP.encode([deployerAddress, BigNumber.from(nonce).toHexString()])), 12));
}

export async function getCreateAddressFor(signer: SignerWithAddress, destination: number): Promise<string> {
  const txCount = await signer.getTransactionCount();
  return getCreateAddress(signer.address, txCount + destination);
}
