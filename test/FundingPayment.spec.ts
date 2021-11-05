import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';

import { FundingPaymentTest } from '../typechain';

const Q128 = BigNumber.from(1).shl(128);
const DAY = 24 * 60 * 60;

describe('FundingPayment', () => {
  let test: FundingPaymentTest;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('FundingPaymentTest')).deploy();
  });

  describe('#a', () => {
    it('rp=101 vp=100 dt=10', async () => {
      const a = await test.nextAX128(10, 20, parsePriceX128(101), parsePriceX128(100));
      expect(a).to.eq(
        Q128.mul(101 - 100)
          .mul(100)
          .div(101)
          .mul(20 - 10)
          .div(DAY),
      ); // (101-100)/101 * 100 * (20-10) / DAY
    });

    it('rp=99 vp=100 dt=10', async () => {
      const a = await test.nextAX128(10, 20, parsePriceX128(99), parsePriceX128(100));
      expect(a).to.eq(
        Q128.mul(99 - 100)
          .mul(100)
          .div(99)
          .mul(20 - 10)
          .div(DAY),
      ); // (101-100)/101 * 100 * (20-10) / DAY
    });
  });

  function parsePriceX128(num: number): BigNumber {
    return BigNumber.from(Math.floor(num))
      .shl(128)
      .add(BigNumber.from((num - Math.floor(num)) * 1e10).mul(ethers.constants.One.shl(128).div(1e10)));
  }

  function formatPriceX128(val: BigNumber): number {
    let formatted = val.shr(128).toNumber();
    formatted += val.mod(ethers.constants.One.shl(128)).mul(1e10).div(ethers.constants.One.shl(128)).toNumber();
    return formatted;
  }
});
