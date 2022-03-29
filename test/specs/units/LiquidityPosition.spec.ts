import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { FakeContract, smock } from '@defi-wonderland/smock';

import {
  SqrtPriceMath,
  TickMath,
  maxLiquidityForAmounts as maxLiquidityForAmounts_,
  ADDRESS_ZERO,
  tickToPrice,
} from '@uniswap/v3-sdk';
// import { constants } from './utils/dummyConstants';
import { LiquidityPositionTest, UniswapV3Pool } from '../../../typechain-types';
import JSBI from 'jsbi';
import { toQ128 } from '../../utils/fixed-point';
import { priceToTick, tickToSqrtPriceX96 } from '../../utils/price-tick';

describe('LiquidityPosition Library', () => {
  let test: LiquidityPositionTest;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  before(async () => {
    const vPoolAddress = ADDRESS_ZERO;
    vPoolFake = await smock.fake<UniswapV3Pool>(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      {
        address: vPoolAddress,
      },
    );
    const tick = -19800;
    const sqrtPriceX96 = tickToSqrtPriceX96(tick);
    vPoolFake.observe.returns([[0, tick * 60], []]);
    vPoolFake.slot0.returns(() => {
      return [sqrtPriceX96, tick, 0, 0, 0, 0, false];
    });
  });

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
      await expect(test.initialize(-1, 1)).to.be.revertedWith('AlreadyInitialized()');
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
      expect(lp.sumALastX128).to.eq(0);
      expect(lp.sumBInsideLastX128).to.eq(0);
      expect(lp.sumFpInsideLastX128).to.eq(0);
      expect(lp.sumFeeInsideLastX128).to.eq(0);
    });

    it('non-zero chkpts', async () => {
      await test.initialize(-1, 1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumAX128: toQ128(10),
        sumBInsideX128: toQ128(20),
        sumFpInsideX128: toQ128(30),
        sumFeeInsideX128: toQ128(40),
      });

      await test.updateCheckpoints();

      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
      expect(lp.liquidity).to.eq(0);
      expect(lp.sumALastX128).to.eq(toQ128(10));
      expect(lp.sumBInsideLastX128).to.eq(toQ128(20));
      expect(lp.sumFpInsideLastX128).to.eq(toQ128(30));
      expect(lp.sumFeeInsideLastX128).to.eq(toQ128(40));
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
      await expect(test.liquidityChange(-1)).to.be.revertedWith('panic code 0x11');
    });
  });

  // describe('#netPosition', () => {
  //   it('sumB=0', async () => {
  //     await test.initialize(-1, 1);

  //     expect(await test.netPosition()).to.eq(0);
  //   });

  //   it('sumB=1 and liquidity=0', async () => {
  //     await test.initialize(-1, 1);

  //     await setWrapperValueInside({
  //       tickLower: -1,
  //       tickUpper: 1,
  //       sumBInsideX128: toQ128(1),
  //     });

  //     expect(await test.netPosition()).to.eq(0, 'should still be 0 as no liquidity');
  //   });

  //   it('sumB=1 and liquidity=1', async () => {
  //     await test.initialize(-1, 1);
  //     await test.liquidityChange(1);

  //     await setWrapperValueInside({
  //       tickLower: -1,
  //       tickUpper: 1,
  //       sumBInsideX128: toQ128(1),
  //     });

  //     expect(await test.netPosition()).to.eq(1, '1*1');
  //   });

  //   it('sumB=-1 and liquidity=1', async () => {
  //     await test.initialize(-1, 1);
  //     await test.liquidityChange(1);

  //     await setWrapperValueInside({
  //       tickLower: -1,
  //       tickUpper: 1,
  //       sumBInsideX128: toQ128(-1),
  //     });

  //     expect(await test.netPosition()).to.eq(-1, '1*-1');
  //   });
  // });

  const vTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  const oneSqrtPrice = BigNumber.from(1).shl(96);

  interface TestCase {
    vQuoteAmount: BigNumberish;
    vTokenAmount: BigNumberish;
    tickLower: number;
    tickUpper: number;
    currentTick: number;
  }

  const testCases: Array<TestCase> = [
    {
      vQuoteAmount: 100,
      vTokenAmount: 100,
      tickLower: -1,
      tickUpper: 1,
      currentTick: 0,
    },
    {
      vQuoteAmount: 100,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 99,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 100,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 101,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -100,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -99,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -101,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: 9001,
    },
    {
      vQuoteAmount: 200,
      vTokenAmount: 100,
      tickLower: -100,
      tickUpper: 100,
      currentTick: -9001,
    },
  ];

  describe('#marketValue', () => {
    it('zero', async () => {
      await test.initialize(-1, 1);
      expect(await test.marketValue(oneSqrtPrice)).to.eq(0);
    });

    testCases.forEach(({ tickLower, tickUpper, currentTick, vQuoteAmount, vTokenAmount }) => {
      it(`ticks ${tickLower} ${tickUpper} | current ${currentTick} | amounts ${vQuoteAmount} ${vTokenAmount}`, async () => {
        const { liquidity, vQuoteActual, vTokenActual, sqrtPriceCurrent } = calculateLiquidityValues({
          vQuoteAmount,
          vTokenAmount,
          tickLower,
          tickUpper,
          currentTick,
          vTokenAddress,
          roundUp: false,
        });

        vPoolFake.slot0.returns(() => {
          return [sqrtPriceCurrent, currentTick, 0, 0, 0, 0, false];
        });

        await test.initialize(tickLower, tickUpper);
        await test.liquidityChange(liquidity);
        //ethers.constants.One.shl(96).mul(ethers.constants.One.shl(96)).div(sqrtPrice);
        // TODO: refactor these tests
        const priceX128 = sqrtPriceCurrent.mul(sqrtPriceCurrent).div(ethers.constants.One.shl(64));

        expect(await test.marketValue(sqrtPriceCurrent)).to.eq(
          vQuoteActual.add(vTokenActual.mul(priceX128).div(ethers.constants.One.shl(128))),
        );
      });
    });
  });

  describe('#maxNetPosition', () => {
    it('zero', async () => {
      await test.initialize(-1, 1);
      expect(await test.maxNetPosition()).to.eq(0);
    });

    testCases.forEach(({ tickLower, tickUpper, currentTick, vQuoteAmount, vTokenAmount }) => {
      it(`ticks ${tickLower} ${tickUpper} | current ${currentTick} | amounts ${vQuoteAmount} ${vTokenAmount}`, async () => {
        const { liquidity, maxNetPosition } = calculateLiquidityValues({
          vQuoteAmount,
          vTokenAmount,
          tickLower,
          tickUpper,
          currentTick,
          vTokenAddress,
          roundUp: true,
        });

        await test.initialize(tickLower, tickUpper);
        await test.liquidityChange(liquidity);

        expect(await test.maxNetPosition()).to.eq(maxNetPosition);
      });
    });
  });

  async function setWrapperValueInside(val: {
    tickLower: number;
    tickUpper: number;
    sumAX128?: BigNumberish;
    sumBInsideX128?: BigNumberish;
    sumFpInsideX128?: BigNumberish;
    sumFeeInsideX128?: BigNumberish;
  }) {
    const wrapper = await hre.ethers.getContractAt('VPoolWrapperMock', await test.wrapper());
    const existingValues = await wrapper.getValuesInside(val.tickLower, val.tickUpper);
    await wrapper.setValuesInside(
      val.tickLower,
      val.tickUpper,
      val.sumAX128 ?? existingValues.sumAX128,
      val.sumBInsideX128 ?? existingValues.sumBInsideX128,
      val.sumFpInsideX128 ?? existingValues.sumFpInsideX128,
      val.sumFeeInsideX128 ?? existingValues.sumFeeInsideX128,
    );
  }

  function mulPrice(amount: BigNumber, sqrtPrice: BigNumber) {
    return amount.mul(sqrtPrice).div(ethers.constants.One.shl(96)).mul(sqrtPrice).div(ethers.constants.One.shl(96));
  }

  function inversex96(sqrtPrice: BigNumber): BigNumber {
    return ethers.constants.One.shl(96).mul(ethers.constants.One.shl(96)).div(sqrtPrice);
  }

  interface CalculateAddLiquidityValuesArgs extends TestCase {
    vTokenAddress: string;
    roundUp: boolean;
  }

  function calculateLiquidityValues({
    vQuoteAmount,
    vTokenAmount,
    tickLower,
    tickUpper,
    currentTick,
    vTokenAddress,
    roundUp,
  }: CalculateAddLiquidityValuesArgs) {
    const sqrtPriceCurrent = TickMath.getSqrtRatioAtTick(currentTick);
    const sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
    const sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
    const amount0 = vTokenAmount;
    const amount1 = vQuoteAmount;

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
    let vQuoteActual: JSBI;
    let maxNetPosition: JSBI;

    vQuoteActual = SqrtPriceMath.getAmount1Delta(sqrtPriceLower, sqrtPriceMiddle, liquidity, roundUp);
    vTokenActual = SqrtPriceMath.getAmount0Delta(sqrtPriceMiddle, sqrtPriceUpper, liquidity, roundUp);
    maxNetPosition = SqrtPriceMath.getAmount0Delta(sqrtPriceLower, sqrtPriceUpper, liquidity, roundUp);

    return {
      liquidity: BigNumber.from(liquidity.toString()),
      vQuoteActual: BigNumber.from(vQuoteActual.toString()),
      vTokenActual: BigNumber.from(vTokenActual.toString()),
      sqrtPriceCurrent: BigNumber.from(sqrtPriceCurrent.toString()),
      maxNetPosition: BigNumber.from(maxNetPosition.toString()),
    };
  }

  function toBigNumber(a: any): BigNumber {
    return BigNumber.from(a.toString());
  }
});
