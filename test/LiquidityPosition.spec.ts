import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { SqrtPriceMath, TickMath, maxLiquidityForAmounts as maxLiquidityForAmounts_ } from '@uniswap/v3-sdk';
import { constants } from './utils/dummyConstants';
import { LiquidityPositionTest } from '../typechain-types';
import JSBI from 'jsbi';

describe('LiquidityPosition Library', () => {
  let test: LiquidityPositionTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('LiquidityPositionTest');
    test = await factory.deploy();
  });

  describe('#initialize', () => {
    it('first works', async () => {
      await test.initialize(-1, 1);
      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
    });

    it('again reverts', async () => {
      await test.initialize(-1, 1);
      expect(test.initialize(-1, 1)).to.be.revertedWith('AlreadyInitialized()');
    });
  });

  describe('#checkpoints', () => {
    it('zero chkpts', async () => {
      await test.initialize(-1, 1);

      await test.updateCheckpoints();
      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
      expect(lp.liquidity).to.eq(0);
      expect(lp.sumALast).to.eq(0);
      expect(lp.sumBInsideLast).to.eq(0);
      expect(lp.sumFpInsideLast).to.eq(0);
      expect(lp.longsFeeGrowthInsideLast).to.eq(0);
      expect(lp.shortsFeeGrowthInsideLast).to.eq(0);
    });

    it('non-zero chkpts', async () => {
      await test.initialize(-1, 1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumA: 10,
        sumBInside: 20,
        sumFpInside: 30,
        longsFeeGrowthInside: 40,
        shortsFeeGrowthInside: 50,
      });

      await test.updateCheckpoints();

      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
      expect(lp.liquidity).to.eq(0);
      expect(lp.sumALast).to.eq(10);
      expect(lp.sumBInsideLast).to.eq(20);
      expect(lp.sumFpInsideLast).to.eq(30);
      expect(lp.longsFeeGrowthInsideLast).to.eq(40);
      expect(lp.shortsFeeGrowthInsideLast).to.eq(50);
    });
  });

  describe('#liquidityChange', () => {
    it('increase', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);
      expect((await test.lp()).liquidity.toNumber()).to.eq(1, '1*1');
    });

    it('decrease', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);
      await test.liquidityChange(-1);
      expect((await test.lp()).liquidity.toNumber()).to.eq(0);
    });

    it('overflow', async () => {
      await test.initialize(-1, 1);
      expect(test.liquidityChange(-1)).to.be.revertedWith('panic code 0x11');
    });
  });

  describe('#netPosition', () => {
    it('sumB=0', async () => {
      await test.initialize(-1, 1);

      expect(await test.netPosition()).to.eq(0);
    });

    it('sumB=1 and liquidity=0', async () => {
      await test.initialize(-1, 1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: 1,
      });

      expect(await test.netPosition()).to.eq(0, 'should still be 0 as no liquidity');
    });

    it('sumB=1 and liquidity=1', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: BigNumber.from(1n<<128n),
      });

      expect(await test.netPosition()).to.eq(1, '1*1');
    });

    it('sumB=-1 and liquidity=1', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: BigNumber.from(1n<<128n).mul(-1),
      });

      expect(await test.netPosition()).to.eq(-1, '1*-1');
    });
  });

  const vTokenAddress = {
    suchThatVTokenIsToken0: ethers.utils.hexZeroPad(BigNumber.from(1).toHexString(), 20),
    suchThatVTokenIsToken1: BigNumber.from(1).shl(160).sub(1).toHexString(),
  };
  const oneSqrtPrice = BigNumber.from(1).shl(96);

  interface TestCase {
    baseAmount: BigNumberish;
    vTokenAmount: BigNumberish;
    tickLower: number;
    tickUpper: number;
    currentTick: number;
  }

  const testCases: Array<TestCase> = [
    {
      baseAmount: 100,
      vTokenAmount: 100,
      tickLower: -1,
      tickUpper: 1,
      currentTick: 0,
    },
    {
      baseAmount: 100,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 99,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 100,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 101,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -100,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -99,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -101,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 9001,
    },
    {
      baseAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -9001,
    },
  ];

  describe('#baseValue', () => {
    it('zero', async () => {
      await test.initialize(-1, 1);
      expect(await test.baseValue(oneSqrtPrice, vTokenAddress.suchThatVTokenIsToken1, constants)).to.eq(0);
    });

    testCases.forEach(({ tickLower, tickUpper, currentTick, baseAmount, vTokenAmount }) => {
      for (const vToken of [vTokenAddress.suchThatVTokenIsToken0, vTokenAddress.suchThatVTokenIsToken1]) {
        const isToken0 = vToken == vTokenAddress.suchThatVTokenIsToken0;
        it(`ticks ${tickLower} ${tickUpper} | current ${currentTick} | amounts ${baseAmount} ${vTokenAmount} | vToken is token${
          isToken0 ? 0 : 1
        }`, async () => {
          const { liquidity, baseActual, vTokenActual, sqrtPriceCurrent } = calculateLiquidityValues({
            baseAmount,
            vTokenAmount,
            tickLower,
            tickUpper,
            currentTick,
            vToken,
            roundUp: false,
          });

          await test.initialize(tickLower, tickUpper);
          await test.liquidityChange(liquidity);
          //ethers.constants.One.shl(96).mul(ethers.constants.One.shl(96)).div(sqrtPrice);
          let priceX128;
          if (!isToken0) {
            let sqrtX96 = inversex96(sqrtPriceCurrent);
            priceX128 = sqrtX96.mul(sqrtX96).div(ethers.constants.One.shl(64));
          } else {
            priceX128 = sqrtPriceCurrent.mul(sqrtPriceCurrent).div(ethers.constants.One.shl(64));
          }
          expect(await test.baseValue(sqrtPriceCurrent, vToken, constants)).to.eq(
            baseActual.add(vTokenActual.mul(priceX128).div(ethers.constants.One.shl(128))),
          );
        });
      }
    });
  });

  describe('#maxNetPosition', () => {
    it('zero', async () => {
      await test.initialize(-1, 1);
      expect(await test.maxNetPosition(vTokenAddress.suchThatVTokenIsToken1, constants)).to.eq(0);
    });

    testCases.forEach(({ tickLower, tickUpper, currentTick, baseAmount, vTokenAmount }) => {
      for (const vToken of [vTokenAddress.suchThatVTokenIsToken0, vTokenAddress.suchThatVTokenIsToken1]) {
        const isToken0 = vToken == vTokenAddress.suchThatVTokenIsToken0;
        it(`ticks ${tickLower} ${tickUpper} | current ${currentTick} | amounts ${baseAmount} ${vTokenAmount} | vToken is token${
          isToken0 ? 0 : 1
        }`, async () => {
          const { liquidity, maxNetPosition } = calculateLiquidityValues({
            baseAmount,
            vTokenAmount,
            tickLower,
            tickUpper,
            currentTick,
            vToken,
            roundUp: true,
          });

          await test.initialize(tickLower, tickUpper);
          await test.liquidityChange(liquidity);

          expect(await test.maxNetPosition(vToken, constants)).to.eq(maxNetPosition);
        });
      }
    });
  });

  async function setWrapperValueInside(val: {
    tickLower: BigNumberish;
    tickUpper: BigNumberish;
    sumA?: BigNumberish;
    sumBInside?: BigNumberish;
    sumFpInside?: BigNumberish;
    longsFeeGrowthInside?: BigNumberish;
    shortsFeeGrowthInside?: BigNumberish;
  }) {
    const wrapper = await hre.ethers.getContractAt('VPoolWrapperMock', await test.wrapper());
    const existingValues = await wrapper.getValuesInside(val.tickLower, val.tickUpper);
    await wrapper.setValuesInside(
      val.tickLower,
      val.tickUpper,
      val.sumA ?? existingValues.sumA,
      val.sumBInside ?? existingValues.sumBInside,
      val.sumFpInside ?? existingValues.sumFpInside,
      val.longsFeeGrowthInside ?? existingValues.longsFeeGrowthInside,
      val.shortsFeeGrowthInside ?? existingValues.shortsFeeGrowthInside,
    );
  }

  function mulPrice(amount: BigNumber, sqrtPrice: BigNumber) {
    return amount.mul(sqrtPrice).div(ethers.constants.One.shl(96)).mul(sqrtPrice).div(ethers.constants.One.shl(96));
  }

  function inversex96(sqrtPrice: BigNumber): BigNumber {
    return ethers.constants.One.shl(96).mul(ethers.constants.One.shl(96)).div(sqrtPrice);
  }

  interface CalculateAddLiquidityValuesArgs extends TestCase {
    vToken: string;
    roundUp: boolean;
  }

  function calculateLiquidityValues({
    baseAmount,
    vTokenAmount,
    tickLower,
    tickUpper,
    currentTick,
    vToken,
    roundUp,
  }: CalculateAddLiquidityValuesArgs) {
    const isToken1 = vToken === vTokenAddress.suchThatVTokenIsToken1;
    const sqrtPriceCurrent = TickMath.getSqrtRatioAtTick(currentTick);
    const sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
    const sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
    const amount0 = vToken === vTokenAddress.suchThatVTokenIsToken0 ? vTokenAmount : baseAmount;
    const amount1 = vToken === vTokenAddress.suchThatVTokenIsToken1 ? vTokenAmount : baseAmount;

    const liquidity = maxLiquidityForAmounts_(
      sqrtPriceCurrent,
      sqrtPriceLower,
      sqrtPriceUpper,
      BigNumber.from(amount0).toString(),
      BigNumber.from(amount1).toString(),
      true,
    );
    let sqrtPriceMiddle = sqrtPriceCurrent;
    if (toBigNumber(sqrtPriceCurrent).lt(toBigNumber(sqrtPriceLower))) {
      sqrtPriceMiddle = sqrtPriceLower;
    } else if (toBigNumber(sqrtPriceCurrent).gt(toBigNumber(sqrtPriceUpper))) {
      sqrtPriceMiddle = sqrtPriceUpper;
    }

    let vTokenActual: JSBI;
    let baseActual: JSBI;
    let maxNetPosition: JSBI;

    if (isToken1) {
      vTokenActual = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceMiddle, liquidity, roundUp);
      baseActual = SqrtPriceMath.getAmount0Delta(sqrtPriceMiddle, sqrtPriceUpper, liquidity, roundUp);
      maxNetPosition = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, roundUp);
    } else {
      baseActual = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceMiddle, liquidity, roundUp);
      vTokenActual = SqrtPriceMath.getAmount0Delta(sqrtPriceMiddle, sqrtPriceUpper, liquidity, roundUp);
      maxNetPosition = SqrtPriceMath.getAmount0Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, roundUp);
    }

    return {
      liquidity: BigNumber.from(liquidity.toString()),
      baseActual: BigNumber.from(baseActual.toString()),
      vTokenActual: BigNumber.from(vTokenActual.toString()),
      sqrtPriceCurrent: BigNumber.from(sqrtPriceCurrent.toString()),
      maxNetPosition: BigNumber.from(maxNetPosition.toString()),
    };
  }

  function toBigNumber(a: any): BigNumber {
    return BigNumber.from(a.toString());
  }
});
