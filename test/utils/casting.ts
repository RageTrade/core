import { BigNumberish, BigNumber } from 'ethers';
import { hexZeroPad } from 'ethers/lib/utils';

export function bytes32(input: BigNumberish): string {
  input = BigNumber.from(input);
  return hexZeroPad(input.toHexString(), 32);
}
