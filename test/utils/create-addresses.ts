import { BigNumber } from '@ethersproject/bignumber';
import { hexDataSlice, keccak256, RLP, getAddress } from 'ethers/lib/utils';

export function getCreateAddress(deployerAddress: string, nonce: number): string {
  return getAddress(hexDataSlice(keccak256(RLP.encode([deployerAddress, BigNumber.from(nonce).toHexString()])), 12));
}
