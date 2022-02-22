import { ethers } from 'ethers';

export function truncate(address: string) {
  return ethers.utils.hexDataSlice(address, 16, 20);
}
