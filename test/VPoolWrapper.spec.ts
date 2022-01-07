import { BigNumber, BigNumberish, FixedNumber } from '@ethersproject/bignumber';
import { ethers } from 'ethers';
import { VPoolWrapperMock2, VBase, VToken, UniswapV3Pool, SimulateSwapTest } from '../typechain-types';
import { SwapEvent } from '../typechain-types/VPoolWrapper';
import { Q128, Q96, toQ128, toQ96 } from './utils/fixed-point';
import { formatEther, formatUnits, parseEther, parseUnits } from '@ethersproject/units';
import {
  initializableTick,
  priceToSqrtPriceX96,
  priceToTick,
  tickToPrice,
  tickToSqrtPriceX96,
} from './utils/price-tick';
import { setupWrapper } from './utils/setup-wrapper';
import { MockContract } from '@defi-wonderland/smock';
import { expect } from 'chai';
import { maxLiquidityForAmounts } from './utils/liquidity';
import { TransferEvent } from '../typechain-types/ERC20';
import { ContractTransaction } from '@ethersproject/contracts';

describe('PoolWrapper', () => {
  let vPoolWrapper: MockContract<VPoolWrapperMock2>;
  let vPool: UniswapV3Pool;
  let vBase: MockContract<VBase>;
  let vToken: MockContract<VToken>;

  interface Range {
    tickLower: number;
    tickUpper: number;
  }

  describe('#liquidityChange', () => {
    let smallerRange: Range;
    let biggerRange: Range;

    before(async () => {
      ({ vPoolWrapper, vPool, vBase, vToken } = await setupWrapper({
        rPriceInitial: 1,
        vPriceInitial: 1,
      }));

      const { tick } = await vPool.slot0();
      // ticks: -100 | -50 | 50 | 100
      biggerRange = {
        tickLower: initializableTick(tick - 100, 10),
        tickUpper: initializableTick(tick + 100, 10),
      };
      smallerRange = {
        tickLower: initializableTick(tick - 50, 10),
        tickUpper: initializableTick(tick + 50, 10),
      };
    });

    it('adds liquidity', async () => {
      await vPoolWrapper.liquidityChange(biggerRange.tickLower, biggerRange.tickUpper, 10_000_000);
      expect(await vPool.liquidity()).to.eq(10_000_000);
    });

    it('removes liquidity', async () => {
      await vPoolWrapper.liquidityChange(biggerRange.tickLower, biggerRange.tickUpper, -4_000_000);
      expect(await vPool.liquidity()).to.eq(6_000_000);
    });

    it('sets tick state to global when tickLower <= tickCurrent', async () => {
      // overwrite the global state
      const fpGlobal = {
        sumAX128: toQ128(1),
        sumBX128: toQ128(2),
        sumFpX128: toQ128(3),
        timestampLast: 100,
      };
      const sumFeeGlobalX128 = toQ128(4);
      vPoolWrapper.setVariable('fpGlobal', fpGlobal);
      vPoolWrapper.setVariable('sumFeeGlobalX128', toQ128(4));

      // add liquidity in the middle
      const { tick } = await vPool.slot0();

      await vPoolWrapper.liquidityChange(smallerRange.tickLower, smallerRange.tickUpper, 4_000_000);

      // lower tick should be set to global state
      const tickLowerState = await vPoolWrapper.ticksExtended(smallerRange.tickLower);
      expect(tickLowerState.sumALastX128).to.eq(fpGlobal.sumAX128);
      expect(tickLowerState.sumBOutsideX128).to.eq(fpGlobal.sumBX128);
      expect(tickLowerState.sumFpOutsideX128).to.eq(fpGlobal.sumFpX128);
      expect(tickLowerState.sumFeeOutsideX128).to.eq(sumFeeGlobalX128);

      // upper tick should not be updated
      const tickUpperState = await vPoolWrapper.ticksExtended(smallerRange.tickUpper);
      expect(tickUpperState.sumALastX128).to.eq(0);
      expect(tickUpperState.sumBOutsideX128).to.eq(0);
      expect(tickUpperState.sumFpOutsideX128).to.eq(0);
      expect(tickUpperState.sumFeeOutsideX128).to.eq(0);

      // bigger range should contain the value
      const valuesInside_100_100 = await vPoolWrapper.getValuesInside(biggerRange.tickLower, biggerRange.tickUpper);
      expect(valuesInside_100_100.sumAX128).to.eq(fpGlobal.sumAX128);
      expect(valuesInside_100_100.sumBInsideX128).to.eq(fpGlobal.sumBX128);
      expect(valuesInside_100_100.sumFpInsideX128).to.eq(fpGlobal.sumFpX128);
      expect(valuesInside_100_100.sumFeeInsideX128).to.eq(sumFeeGlobalX128);

      // by default given to lower range
      const valuesInside_100_50 = await vPoolWrapper.getValuesInside(biggerRange.tickLower, smallerRange.tickLower);
      expect(valuesInside_100_50.sumAX128).to.eq(fpGlobal.sumAX128);
      expect(valuesInside_100_50.sumBInsideX128).to.eq(fpGlobal.sumBX128);
      expect(valuesInside_100_50.sumFpInsideX128).to.eq(fpGlobal.sumFpX128);
      expect(valuesInside_100_50.sumFeeInsideX128).to.eq(sumFeeGlobalX128);

      // smaller range should give zero
      const valuesInside_50_50 = await vPoolWrapper.getValuesInside(smallerRange.tickLower, smallerRange.tickUpper);
      expect(valuesInside_50_50.sumAX128).to.eq(fpGlobal.sumAX128); // just gives global val
      expect(valuesInside_50_50.sumBInsideX128).to.eq(0);
      expect(valuesInside_50_50.sumFpInsideX128).to.eq(0);
      expect(valuesInside_50_50.sumFeeInsideX128).to.eq(0);

      // upper range should give zero
      const valuesInside_50_100 = await vPoolWrapper.getValuesInside(smallerRange.tickUpper, biggerRange.tickUpper);
      expect(valuesInside_50_100.sumAX128).to.eq(fpGlobal.sumAX128); // just gives global val
      expect(valuesInside_50_100.sumBInsideX128).to.eq(0);
      expect(valuesInside_50_100.sumFpInsideX128).to.eq(0);
      expect(valuesInside_50_100.sumFeeInsideX128).to.eq(0);
    });
  });

  describe('#getValuesInside', () => {
    const uniswapFee = 500;
    const liquidityFee = 1000;
    const protocolFee = 500;
    // const uniswapFee = 500;
    // const liquidityFee = 700;
    // const protocolFee = 300;

    let liquidity1: BigNumber;
    let liquidity2: BigNumber;
    beforeEach(async () => {
      // sets up the liquidity
      // -20 -> -10 ===> 100 A (liquidity2)
      // -10 ->   0 ===> 100 A (liquidity1)
      //   0 ->  10 ===> 100 B (liquidity1)
      //  10 ->  20 ===> 100 B (liquidity2)
      ({ vPoolWrapper, vPool, vBase, vToken } = await setupWrapper({
        rPriceInitial: 1,
        vPriceInitial: 1,
        vBaseDecimals: 18,
        vTokenDecimals: 18,
        uniswapFee,
        liquidityFee,
        protocolFee,
      }));

      const { sqrtPriceX96 } = await vPool.slot0();
      liquidity1 = maxLiquidityForAmounts(sqrtPriceX96, -10, 10, parseUnits('100', 18), parseUnits('100', 18), true);
      liquidity2 = maxLiquidityForAmounts(sqrtPriceX96, 10, 20, parseUnits('100', 18), parseUnits('100', 18), true);

      await vPoolWrapper.liquidityChange(-10, 10, liquidity1);
      await vPoolWrapper.liquidityChange(10, 20, liquidity2);
      await vPoolWrapper.liquidityChange(-20, -10, liquidity2);
    });

    describe('lp sumB', () => {
      const cases = [
        { isNotional: false, tradeAmount: parseEther('1'), info: 'exactOut ETH' },
        { isNotional: false, tradeAmount: parseEther('-1'), info: 'exactIn ETH' },
        { isNotional: true, tradeAmount: parseEther('2'), info: 'exactOut USDC' },
        { isNotional: true, tradeAmount: parseEther('-2'), info: 'exactIn USDC' },
      ];

      describe('no tick cross', () => {
        it('buy | exactIn vBase', async () => {
          const amountSpecified = parseUnits('50', 18); // vBase
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(false, amountSpecified, 0));

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);

          const expectedSumBIncrease = SwapEvent.args.vTokenIn
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumBX128).to.eq(expectedSumBIncrease);

          // just after first trade, the initial values of sumA and sumFp are still zero
          expect(valuesInside20.sumAX128).to.eq(0);
          expect(valuesInside20.sumFpInsideX128).to.eq(0);
        });

        it('buy | exactOut vToken', async () => {
          const amountSpecified = parseUnits('-50', 18); // vToken
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(false, amountSpecified, 0));
          expect(SwapEvent.args.vTokenIn.abs()).eq(amountSpecified.abs());

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);

          const expectedSumBIncrease = SwapEvent.args.vTokenIn
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumBX128).to.eq(expectedSumBIncrease);

          // just after first trade, the initial values of sumA and sumFp are still zero
          expect(valuesInside20.sumAX128).to.eq(0);
          expect(valuesInside20.sumFpInsideX128).to.eq(0);
        });

        it('sell | exactIn vToken', async () => {
          const amountSpecified = parseUnits('50', 18); // vToken
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(true, amountSpecified, 0));
          expect(SwapEvent.args.vTokenIn.abs()).eq(amountSpecified.abs());

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);

          const expectedSumBIncrease = SwapEvent.args.vTokenIn
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumBX128).to.eq(expectedSumBIncrease);

          // just after first trade, the initial values of sumA and sumFp are still zero
          expect(valuesInside20.sumAX128).to.eq(0);
          expect(valuesInside20.sumFpInsideX128).to.eq(0);
        });

        it('sell | exactOut vBase', async () => {
          const amountSpecified = parseUnits('-50', 18); // vBase
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(true, amountSpecified, 0));

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);

          const expectedSumBIncrease = SwapEvent.args.vTokenIn
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumBX128).to.eq(expectedSumBIncrease);

          // just after first trade, the initial values of sumA and sumFp are still zero
          expect(valuesInside20.sumAX128).to.eq(0);
          expect(valuesInside20.sumFpInsideX128).to.eq(0);
        });
      });

      describe('single tick cross', () => {
        it('buy | exactIn vBase', async () => {
          const amountSpecified = parseUnits('150', 18); // vBase
          await vPoolWrapper.swap(false, amountSpecified, 0);

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const values2020 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(values2020.sumBInsideX128).to.eq(globalState.sumBX128);

          // since trade went other way, there should not be any net position in one side
          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          expect(values2010.sumBInsideX128).to.eq(0);

          // sum of net positions in individual ranges should equal global net position
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1010.sumBInsideX128).to.not.eq(0);
          expect(values1020.sumBInsideX128).to.not.eq(0);
          expect(values1010.sumBInsideX128.add(values1020.sumBInsideX128)).to.eq(globalState.sumBX128);
        });

        it('buy | exactOut vToken', async () => {
          const amountSpecified = parseUnits('150', 18); // vToken
          await vPoolWrapper.swap(false, amountSpecified, 0);

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const values2020 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(values2020.sumBInsideX128).to.eq(globalState.sumBX128);

          // since trade went other way, there should not be any net position in one side
          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          expect(values2010.sumBInsideX128).to.eq(0);

          // sum of net positions in individual ranges should equal global net position
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1010.sumBInsideX128).to.not.eq(0);
          expect(values1020.sumBInsideX128).to.not.eq(0);
          expect(values1010.sumBInsideX128.add(values1020.sumBInsideX128)).to.eq(globalState.sumBX128);
        });

        it('sell | exactIn vToken', async () => {
          const amountSpecified = parseUnits('150', 18); // vToken
          await vPoolWrapper.swap(true, amountSpecified, 0);

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const values2020 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(values2020.sumBInsideX128).to.eq(globalState.sumBX128);

          // sum of net positions in individual ranges should equal global net position
          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          expect(values2010.sumBInsideX128).to.not.eq(0);
          expect(values1010.sumBInsideX128).to.not.eq(0);
          expect(values2010.sumBInsideX128.add(values1010.sumBInsideX128)).to.eq(globalState.sumBX128);

          // since trade went other way, there should not be any net position in one side
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1020.sumBInsideX128).to.eq(0);
        });

        it('sell | exactOut vBase', async () => {
          const amountSpecified = parseUnits('-150', 18); // vBase
          await vPoolWrapper.swap(true, amountSpecified, 0);

          const globalState = await getGlobal();

          // since no trades went outside -20 and 20, values inside should be same as global
          const values2020 = await vPoolWrapper.getValuesInside(-20, 20);
          expect(values2020.sumBInsideX128).to.eq(globalState.sumBX128);

          // sum of net positions in individual ranges should equal global net position
          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          expect(values2010.sumBInsideX128).to.not.eq(0);
          expect(values1010.sumBInsideX128).to.not.eq(0);
          expect(values2010.sumBInsideX128.add(values1010.sumBInsideX128)).to.eq(globalState.sumBX128);

          // since trade went other way, there should not be any net position in one side
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1020.sumBInsideX128).to.eq(0);
        });
      });
    });

    describe('lp fees', () => {
      describe('no tick cross', () => {
        it('buy | exactIn vBase', async () => {
          const amountSpecified = parseUnits('50', 18);
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(false, amountSpecified, 0));

          const globalState = await getGlobal();
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

          // since no trades went outside -20 and 20, values inside should be same as global
          expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

          const expectedFeeIncrease = SwapEvent.args.liquidityFees
            .sub(1) // TODO why this sub 1 is needed, fix this
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumFeeGlobalX128).to.eq(expectedFeeIncrease);
        });

        it('buy | exactOut vToken', async () => {
          const amountSpecified = parseUnits('-50', 18);
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(false, amountSpecified, 0));

          const globalState = await getGlobal();
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

          // since no trades went outside -20 and 20, values inside should be same as global
          expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

          const expectedFeeIncrease = SwapEvent.args.liquidityFees
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumFeeGlobalX128).to.eq(expectedFeeIncrease);
        });

        it('sell | exactOut vBase', async () => {
          const amountSpecified = parseUnits('-50', 18);
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(true, amountSpecified, 0));

          const globalState = await getGlobal();
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

          // since no trades went outside -20 and 20, values inside should be same as global
          expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

          const expectedFeeIncrease = SwapEvent.args.liquidityFees
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumFeeGlobalX128).to.eq(expectedFeeIncrease);
        });

        it('sell | exactIn vToken', async () => {
          const amountSpecified = parseUnits('50', 18);
          const SwapEvent = await extractSwapEvent(vPoolWrapper.swap(true, amountSpecified, 0));

          const globalState = await getGlobal();
          const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

          // since no trades went outside -20 and 20, values inside should be same as global
          expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

          const expectedFeeIncrease = SwapEvent.args.liquidityFees
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1);
          expect(globalState.sumFeeGlobalX128).to.eq(expectedFeeIncrease);
        });
      });

      describe('single tick cross', () => {
        it('buy | exactIn vBase', async () => {
          const amountSpecified = parseUnits('150', 18);
          await vPoolWrapper.swap(false, amountSpecified, 0);

          const { sumFeeGlobalX128 } = await getGlobal();

          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          expect(values2010.sumFeeInsideX128).to.eq(0);

          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1010.sumFeeInsideX128).to.not.eq(0);
          expect(values1020.sumFeeInsideX128).to.not.eq(0);
          expect(values1010.sumFeeInsideX128.add(values1020.sumFeeInsideX128)).to.eq(sumFeeGlobalX128);
        });

        it('buy | exactOut vToken', async () => {
          const amountSpecified = parseUnits('-150', 18);
          await vPoolWrapper.swap(false, amountSpecified, 0);
          const { sumFeeGlobalX128 } = await getGlobal();

          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          expect(values2010.sumFeeInsideX128).to.eq(0);

          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1010.sumFeeInsideX128).to.not.eq(0);
          expect(values1020.sumFeeInsideX128).to.not.eq(0);
          expect(values1010.sumFeeInsideX128.add(values1020.sumFeeInsideX128)).to.eq(sumFeeGlobalX128);
        });

        it('sell | exactIn vToken', async () => {
          const amountSpecified = parseUnits('150', 18);
          await vPoolWrapper.swap(true, amountSpecified, 0);

          const { sumFeeGlobalX128 } = await getGlobal();

          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          expect(values2010.sumFeeInsideX128).to.not.eq(0);
          expect(values1010.sumFeeInsideX128).to.not.eq(0);
          expect(values2010.sumFeeInsideX128.add(values1010.sumFeeInsideX128)).to.eq(sumFeeGlobalX128);

          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1020.sumFeeInsideX128).to.eq(0);
        });

        it('sell | exactOut vBase', async () => {
          const amountSpecified = parseUnits('-150', 18);
          await vPoolWrapper.swap(true, amountSpecified, 0);

          const { sumFeeGlobalX128 } = await getGlobal();

          const values2010 = await vPoolWrapper.getValuesInside(-20, -10);
          const values1010 = await vPoolWrapper.getValuesInside(-10, 10);
          expect(values2010.sumFeeInsideX128).to.not.eq(0);
          expect(values1010.sumFeeInsideX128).to.not.eq(0);
          expect(values2010.sumFeeInsideX128.add(values1010.sumFeeInsideX128)).to.eq(sumFeeGlobalX128);

          const values1020 = await vPoolWrapper.getValuesInside(10, 20);
          expect(values1020.sumFeeInsideX128).to.eq(0);
        });
      });
    });
  });

  async function liquidityChange(priceLower: number, priceUpper: number, liquidityDelta: BigNumberish) {
    const tickSpacing = await vPool.tickSpacing();
    let tickLower = await priceToTick(priceLower, vBase, vToken);
    let tickUpper = await priceToTick(priceUpper, vBase, vToken);
    tickLower -= tickLower % tickSpacing;
    tickUpper -= tickUpper % tickSpacing;

    const priceLowerActual = await tickToPrice(tickLower, vBase, vToken);
    const priceUpperActual = await tickToPrice(tickUpper, vBase, vToken);
    // console.log(
    //   `adding liquidity between ${priceLowerActual} (tick: ${tickLower}) and ${priceUpperActual} (tick: ${tickUpper})`,
    // );

    await vPoolWrapper.liquidityChange(tickLower, tickUpper, liquidityDelta);
  }

  async function extractTransferEvents(tx: ContractTransaction | Promise<ContractTransaction>) {
    tx = await tx;
    const rc = await tx.wait();
    const transferEvents = rc.logs
      ?.map(log => {
        try {
          return { ...log, ...vToken.interface.parseLog(log) };
        } catch {
          return null;
        }
      })
      .filter(event => event !== null)
      .filter(event => event?.name === 'Transfer') as unknown as TransferEvent[];

    return {
      vTokenMintEvent: transferEvents.find(
        event => event.address === vToken.address && event.args.from === ethers.constants.AddressZero,
      ),
      vTokenBurnEvent: transferEvents.find(
        event => event.address === vToken.address && event.args.to === ethers.constants.AddressZero,
      ),
      vBaseMintEvent: transferEvents.find(
        event => event.address === vBase.address && event.args.from === ethers.constants.AddressZero,
      ),
      vBaseBurnEvent: transferEvents.find(
        event => event.address === vBase.address && event.args.to === ethers.constants.AddressZero,
      ),
    };
  }
  async function extractSwapEvent(tx: ContractTransaction | Promise<ContractTransaction>) {
    tx = await tx;
    const rc = await tx.wait();
    const SwapEvent = (
      rc.logs
        ?.map(log => {
          try {
            return { ...log, ...vPoolWrapper.interface.parseLog(log) };
          } catch {
            return null;
          }
        })
        .filter(event => event !== null)
        .filter(event => event?.name === 'Swap') as unknown as SwapEvent[]
    ).find(event => event.address === vPoolWrapper.address);
    if (!SwapEvent) {
      throw new Error('SwapEvent was not emitted');
    }
    return SwapEvent;
  }

  async function getGlobal(): Promise<{
    sumAX128: BigNumber;
    sumBX128: BigNumber;
    sumFpX128: BigNumber;
    timestampLast: number;
    sumFeeGlobalX128: BigNumber;
  }> {
    const fpGlobal = await vPoolWrapper.fpGlobal();
    // const uniswapFeeX128 = await vPool.feeGrowthGlobal1X128();
    const sumFeeGlobalX128 = await vPoolWrapper.sumFeeGlobalX128();
    return { ...fpGlobal, sumFeeGlobalX128 };
  }

  function parseUsdc(str: string): BigNumber {
    return parseUnits(str.replaceAll(',', '').replaceAll('_', ''), 6);
  }
});
