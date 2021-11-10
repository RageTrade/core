import { BigNumber, ethers } from 'ethers';

export const Q128 = BigNumber.from(1).shl(128);

export function toQ128(num: number): BigNumber {
  const frac = num - Math.floor(num);
  num -= frac;
  return Q128.mul(num).add(
    BigNumber.from(Math.floor(Number.MAX_SAFE_INTEGER * frac))
      .mul(Q128)
      .div('0x1fffffffffffff'), // Number.MAX_SAFE_INTEGER
  );
}

export function fromQ128(val: BigNumber): number {
  let formatted = val.shr(128).toNumber();
  formatted +=
    val
      .mod(Q128)
      .mul(Number.MAX_SAFE_INTEGER - 1)
      .div(Q128)
      .toNumber() /
    (Number.MAX_SAFE_INTEGER - 1);
  return formatted;
}
