import { ethers } from 'ethers';

export function truncate(address: string) {
  return ethers.utils.hexDataSlice(address, 0, 4);
}
