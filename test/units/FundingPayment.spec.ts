import { BigNumber } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { BigNumberish } from 'ethers';
import hre, { ethers } from 'hardhat';

import { FundingPaymentTest } from '../../typechain-types';
import { Q128, toQ128 } from '../helpers/fixed-point';

const DAY = 24 * 60 * 60;

describe('FundingPayment', () => {
  let test: FundingPaymentTest;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('FundingPaymentTest')).deploy();
  });

  describe('#a', () => {
    it('rp=101 vp=100 dt=10', async () => {
      const a = await test.nextAX128(10, 20, toQ128(101), toQ128(100));
      expect(a.gt(0)).to.be.true;
      expect(a).to.eq(
        Q128.mul(101 - 100)
          .mul(100)
          .div(101)
          .mul(20 - 10)
          .div(DAY),
      ); // (101-100)/101 * 100 * (20-10) / DAY
    });

    it('rp=99 vp=100 dt=10', async () => {
      const a = await test.nextAX128(10, 20, toQ128(99), toQ128(100));
      expect(a.gt(0)).to.be.false;
      expect(a).to.eq(
        Q128.mul(99 - 100)
          .mul(100)
          .div(99)
          .mul(20 - 10)
          .div(DAY),
      ); // (101-100)/101 * 100 * (20-10) / DAY
    });

    it('rp=1.01 vp=1 dt=10', async () => {
      const a = await test.nextAX128(10, 20, toQ128(1.01), toQ128(1));
      expect(a.gt(0)).to.be.true;
      expect(a).to.eq(
        toQ128(1.01)
          .sub(toQ128(1)) // rp - vp
          .mul(toQ128(1)) // vp
          .div(toQ128(1.01)) // rp
          .mul(20 - 10) // dt
          .div(DAY),
      ); // (101-100)/101 * 100 * (20-10) / DAY
    });
  });

  describe('#update', () => {
    const realPrice = toQ128(1.01);
    const virtualPrice = toQ128(1);
    it('initial', async () => {
      const { sumAX128, sumBX128, sumFpX128, timestampLast } = await test.fpGlobal();
      expect(sumAX128).to.eq(0);
      expect(sumBX128).to.eq(0);
      expect(sumFpX128).to.eq(0);
      expect(timestampLast).to.eq(0);
    });

    it(`one long`, async () => {
      const vTokenAmount = 100;
      const liquidity = 10000;
      const blockTimestamp = 1;
      await update({
        vTokenAmount,
        liquidity,
        blockTimestamp,
        realPrice,
        virtualPrice,
      });

      const { sumAX128, sumBX128, sumFpX128, timestampLast } = await test.fpGlobal();
      expect(sumAX128).to.eq(realPrice.sub(virtualPrice).mul(virtualPrice).div(realPrice).div(DAY));
      expect(sumBX128).to.eq(Q128.mul(vTokenAmount).div(liquidity));
      expect(sumFpX128).to.eq(0);
      expect(timestampLast).to.eq(blockTimestamp);
    });

    it(`one short`, async () => {
      const vTokenAmount = -100;
      const liquidity = 10000;
      const blockTimestamp = 1;
      await update({
        vTokenAmount,
        liquidity,
        blockTimestamp,
        realPrice,
        virtualPrice,
      });

      const { sumAX128, sumBX128, sumFpX128, timestampLast } = await test.fpGlobal();
      expect(sumAX128).to.eq(realPrice.sub(virtualPrice).mul(virtualPrice).div(realPrice).div(DAY));
      expect(sumBX128).to.eq(Q128.mul(vTokenAmount).div(liquidity));
      expect(sumFpX128).to.eq(0);
      expect(timestampLast).to.eq(blockTimestamp);
    });

    it(`two longs`, async () => {
      const vTokenAmount1 = 100;
      const liquidity1 = 10000;
      const blockTimestamp1 = 1;
      await update({
        vTokenAmount: vTokenAmount1,
        liquidity: liquidity1,
        blockTimestamp: blockTimestamp1,
        realPrice,
        virtualPrice,
      });

      const vTokenAmount2 = 200;
      const liquidity2 = 5000;
      const blockTimestamp2 = 3;
      await update({
        vTokenAmount: vTokenAmount2,
        liquidity: liquidity2,
        blockTimestamp: blockTimestamp2,
        realPrice,
        virtualPrice,
      });

      const a1 = realPrice
        .sub(virtualPrice)
        .mul(virtualPrice)
        .div(realPrice)
        .mul(blockTimestamp2 - blockTimestamp1)
        .div(DAY);
      const a2 = realPrice.sub(virtualPrice).mul(virtualPrice).div(realPrice).mul(blockTimestamp1).div(DAY);

      const b1 = Q128.mul(vTokenAmount1).div(liquidity1);
      const b2 = Q128.mul(vTokenAmount2).div(liquidity2);

      const { sumAX128, sumBX128, sumFpX128, timestampLast } = await test.fpGlobal();
      expect(sumAX128).to.eq(a1.add(a2));
      expect(sumBX128).to.eq(b1.add(b2));
      expect(sumFpX128).to.eq(a1.mul(b1).div(Q128));
      expect(timestampLast).to.eq(blockTimestamp2);
    });

    it(`two shorts`, async () => {
      const vTokenAmount1 = -100;
      const liquidity1 = 10000;
      const blockTimestamp1 = 1;
      await update({
        vTokenAmount: vTokenAmount1,
        liquidity: liquidity1,
        blockTimestamp: blockTimestamp1,
        realPrice,
        virtualPrice,
      });

      const vTokenAmount2 = 200;
      const liquidity2 = 5000;
      const blockTimestamp2 = 3;
      await update({
        vTokenAmount: vTokenAmount2,
        liquidity: liquidity2,
        blockTimestamp: blockTimestamp2,
        realPrice,
        virtualPrice,
      });

      const a1 = realPrice
        .sub(virtualPrice)
        .mul(virtualPrice)
        .div(realPrice)
        .mul(blockTimestamp2 - blockTimestamp1)
        .div(DAY);
      const a2 = realPrice.sub(virtualPrice).mul(virtualPrice).div(realPrice).mul(blockTimestamp1).div(DAY);

      const b1 = Q128.mul(vTokenAmount1).div(liquidity1);
      const b2 = Q128.mul(vTokenAmount2).div(liquidity2);

      const { sumAX128, sumBX128, sumFpX128, timestampLast } = await test.fpGlobal();
      expect(sumAX128).to.eq(a1.add(a2));
      expect(sumBX128).to.eq(b1.add(b2));
      expect(sumFpX128).to.eq(ifNegThenSubOne(a1.mul(b1).div(Q128)));
      expect(timestampLast).to.eq(blockTimestamp2);
    });
  });

  async function update({
    vTokenAmount,
    liquidity,
    blockTimestamp,
    realPrice,
    virtualPrice,
  }: {
    vTokenAmount: BigNumberish;
    liquidity: BigNumberish;
    blockTimestamp: BigNumberish;
    realPrice?: BigNumber | number;
    virtualPrice?: BigNumber | number;
  }) {
    await test.update(
      vTokenAmount,
      liquidity,
      blockTimestamp,
      BigNumber.isBigNumber(realPrice) ? realPrice : toQ128(realPrice ?? 1.01),
      BigNumber.isBigNumber(virtualPrice) ? virtualPrice : toQ128(virtualPrice ?? 1),
    );
  }

  function ifNegThenSubOne(bn: BigNumber) {
    if (bn.lt(0)) bn = bn.sub(1);
    return bn;
  }
});
