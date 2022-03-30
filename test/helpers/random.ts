import { hexlify, randomBytes } from 'ethers/lib/utils';

export function randomAddress() {
  return hexlify(randomBytes(20));
}
