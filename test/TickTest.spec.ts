import hre from 'hardhat';
import { TickTest, UniswapV3PoolMock } from '../typechain';
import { BigNumber, BigNumberish, ethers } from 'ethers';
import { expect } from 'chai';

describe('Tick', () => {
  let test: TickTest;
  let vPool: UniswapV3PoolMock;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('TickTest')).deploy();
    vPool = await hre.ethers.getContractAt('UniswapV3PoolMock', await test.vPool());
  });

  describe('#fundingPaymentGrowthInside', () => {
    it('zero', async () => {
      expect(await test.getFundingPaymentGrowthInside(-1, 1, 0, 0, 0)).to.eq(0);
    });

    it('current price inside, global increase', async () => {
      expect(await test.getFundingPaymentGrowthInside(-1, 1, 0, 0, 10)).to.eq(10);
    });

    it('current price outside, global increase', async () => {
      expect(await test.getFundingPaymentGrowthInside(-1, 1, 2, 0, 10)).to.eq(0);
    });

    it('current price inside, global increase with ticks', async () => {
      await setTick(-1, { sumFpOutside: 5 });
      await setTick(1, { sumFpOutside: 10 });
      expect(await test.getFundingPaymentGrowthInside(-1, 1, 0, 0, 30)).to.eq(15);
    });

    it('current price outside, global increase with ticks', async () => {
      await setTick(-1, { sumFpOutside: 5 });
      await setTick(1, { sumFpOutside: 10 });

      expect(await test.getFundingPaymentGrowthInside(-1, 1, 2, 0, 30)).to.eq(5);
    });

    it('current price outside, global increase with ticks and extrapolation', async () => {
      await setTick(-1, { sumFpOutside: 5 });
      await setTick(1, { sumFpOutside: 10, sumBOutside: 10 });

      // extrapolated fp in -1 to 1 would be 10x10 = 100
      expect(await test.getFundingPaymentGrowthInside(-1, 1, 2, 10, 30)).to.eq(100 + 5);
    });
  });

  const vTokenAddress = {
    suchThatVTokenIsToken0: ethers.utils.hexZeroPad(BigNumber.from(1).toHexString(), 20),
    suchThatVTokenIsToken1: BigNumber.from(1).shl(160).sub(1).toHexString(),
  };
  describe('#uniswapFeeGrowth', () => {
    it('zero', async () => {
      expect(await test.getUniswapFeeGrowthInside(-1, 1, 0, vTokenAddress.suchThatVTokenIsToken0)).to.eq(0);
    });

    it('current price inside, global increase', async () => {
      await vPool.setFeeGrowth(0, 10); // increasing token1 global var
      expect(await test.getUniswapFeeGrowthInside(-1, 1, 0, vTokenAddress.suchThatVTokenIsToken0)).to.eq(10);
    });

    it('current price outside, global increase', async () => {
      await vPool.setFeeGrowth(0, 10); // increasing token1 global var
      expect(await test.getUniswapFeeGrowthInside(-1, 1, 2, vTokenAddress.suchThatVTokenIsToken0)).to.eq(0);
    });

    it('current price inside, global increase with ticks', async () => {
      await vPool.setFeeGrowth(0, 30); // increasing token1 global var
      await vPoolMocksetTick(-1, { feeGrowthOutside1X128: 5 });
      await vPoolMocksetTick(1, { feeGrowthOutside1X128: 10 });
      expect(await test.getUniswapFeeGrowthInside(-1, 1, 0, vTokenAddress.suchThatVTokenIsToken0)).to.eq(15);
    });

    it('current price outside, global increase with ticks', async () => {
      await vPool.setFeeGrowth(0, 30); // increasing token1 global var
      await vPoolMocksetTick(-1, { feeGrowthOutside1X128: 5 });
      await vPoolMocksetTick(1, { feeGrowthOutside1X128: 10 });
      expect(await test.getUniswapFeeGrowthInside(-1, 1, 2, vTokenAddress.suchThatVTokenIsToken0)).to.eq(5);
    });
  });

  describe('#extendedFeeGrowth', () => {
    it('zero', async () => {
      expect(await test.getExtendedFeeGrowthInside(-1, 1, 0, 0)).to.eq(0);
    });

    it('current price inside, global increase', async () => {
      expect(await test.getExtendedFeeGrowthInside(-1, 1, 0, 10)).to.eq(10);
    });

    it('current price outside, global increase', async () => {
      expect(await test.getExtendedFeeGrowthInside(-1, 1, 2, 10)).to.eq(0);
    });

    it('current price inside, global increase with ticks', async () => {
      await setTick(-1, { extendedFeeGrowthOutsideX128: 5 });
      await setTick(1, { extendedFeeGrowthOutsideX128: 10 });
      expect(await test.getExtendedFeeGrowthInside(-1, 1, 0, 30)).to.eq(15);
    });

    it('current price outside, global increase with ticks', async () => {
      await setTick(-1, { extendedFeeGrowthOutsideX128: 5 });
      await setTick(1, { extendedFeeGrowthOutsideX128: 10 });

      expect(await test.getExtendedFeeGrowthInside(-1, 1, 2, 30)).to.eq(5);
    });
  });

  async function setTick(
    tickIndex: number,
    {
      sumALast,
      sumBOutside,
      sumFpOutside,
      extendedFeeGrowthOutsideX128,
    }: {
      sumALast?: BigNumberish;
      sumBOutside?: BigNumberish;
      sumFpOutside?: BigNumberish;
      extendedFeeGrowthOutsideX128?: BigNumberish;
    },
  ) {
    const tick = await test.extendedTicks(tickIndex);
    if (sumALast === undefined) sumALast = tick.sumALast;
    if (sumBOutside === undefined) sumBOutside = tick.sumBOutside;
    if (sumFpOutside === undefined) sumFpOutside = tick.sumFpOutside;
    if (extendedFeeGrowthOutsideX128 === undefined) extendedFeeGrowthOutsideX128 = tick.extendedFeeGrowthOutsideX128;
    await test.setTick(tickIndex, { sumALast, sumBOutside, sumFpOutside, extendedFeeGrowthOutsideX128 });
  }

  async function vPoolMocksetTick(
    tickIndex: number,
    {
      liquidityGross,
      liquidityNet,
      feeGrowthOutside0X128,
      feeGrowthOutside1X128,
      tickCumulativeOutside,
      secondsPerLiquidityOutsideX128,
      secondsOutside,
      initialized,
    }: {
      liquidityGross?: BigNumberish;
      liquidityNet?: BigNumberish;
      feeGrowthOutside0X128?: BigNumberish;
      feeGrowthOutside1X128?: BigNumberish;
      tickCumulativeOutside?: BigNumberish;
      secondsPerLiquidityOutsideX128?: BigNumberish;
      secondsOutside?: BigNumberish;
      initialized?: boolean;
    },
  ) {
    const tick = await vPool.ticks(tickIndex);
    if (liquidityGross === undefined) liquidityGross = tick.liquidityGross;
    if (liquidityNet === undefined) liquidityNet = tick.liquidityNet;
    if (feeGrowthOutside0X128 === undefined) feeGrowthOutside0X128 = tick.feeGrowthOutside0X128;
    if (feeGrowthOutside1X128 === undefined) feeGrowthOutside1X128 = tick.feeGrowthOutside1X128;
    if (tickCumulativeOutside === undefined) tickCumulativeOutside = tick.tickCumulativeOutside;
    if (secondsPerLiquidityOutsideX128 === undefined)
      secondsPerLiquidityOutsideX128 = tick.secondsPerLiquidityOutsideX128;
    if (secondsOutside === undefined) secondsOutside = tick.secondsOutside;
    if (initialized === undefined) initialized = tick.initialized;
    await vPool.setTick(
      tickIndex,
      liquidityGross,
      liquidityNet,
      feeGrowthOutside0X128,
      feeGrowthOutside1X128,
      tickCumulativeOutside,
      secondsPerLiquidityOutsideX128,
      secondsOutside,
      initialized,
    );
  }
});
