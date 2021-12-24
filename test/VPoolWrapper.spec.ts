import { BigNumber, BigNumberish, FixedNumber } from '@ethersproject/bignumber';
import hre, { ethers } from 'hardhat';
import { VPoolWrapper, VPoolFactory, ERC20, VBase, VToken, UniswapV3Pool, ERC20__factory } from '../typechain-types';
import { ERC20Interface } from '../typechain-types/ERC20';
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
  let vPoolWrapper: MockContract<VPoolWrapper>;
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

  describe('#swap', () => {
    let uniswapFee: number;
    let liquidityFee: number;
    let protocolFee: number;

    before(async () => {
      ({ vPoolWrapper, vPool, vBase, vToken } = await setupWrapper({
        rPriceInitial: 2000,
        vPriceInitial: 2000,
        uniswapFee: 500,
        // TODO: fuzz various liquidity and protocol fees
        liquidityFee: 700,
        protocolFee: 300,
      }));

      expect((uniswapFee = await vPoolWrapper.uniswapFeePips())).to.eq(500);
      expect((liquidityFee = await vPoolWrapper.liquidityFeePips())).to.eq(700);
      expect((protocolFee = await vPoolWrapper.protocolFeePips())).to.eq(300);

      // const { tick, sqrtPriceX96 } = await vPool.slot0();

      // bootstraping initial liquidity
      await liquidityChange(1000, 2000, 10n ** 15n); // here usdc should be put
      await liquidityChange(2000, 3000, 10n ** 15n); // here vtoken should be put
      await liquidityChange(3000, 4000, 10n ** 15n); // here vtoken should be put
      await liquidityChange(4000, 5000, 10n ** 15n);
      await liquidityChange(1000, 4000, 10n ** 15n); // here vtoken should be put
    });

    it('buy 1 ETH (exactOut 1 ETH)', async () => {
      const { vTokenIn } = await vPoolWrapper.callStatic.swap(false, parseEther('1'), 0);

      // when asked for 1 ETH output, trader should get that exactly and be charged whatever USDC it is
      expect(vTokenIn.mul(-1)).to.eq(parseEther('1'));

      const { vTokenBurnEvent } = await extractEvents(vPoolWrapper.swap(false, parseEther('1'), 0));
      if (!vTokenBurnEvent) {
        throw new Error('vTokenBurnEvent not emitted');
      }
      // vToken ERC0 tokens that are bought, are burned by the vPoolWrapper
      // and just the value is returned to ClearingHouse
      expect(vTokenBurnEvent.args.value).to.eq(parseEther('1'));
    });

    it('buy ETH worth 2000 USDC (exactIn 2000 USDC)', async () => {
      const { vBaseIn } = await vPoolWrapper.callStatic.swap(true, parseUsdc('2000'), 0);

      // when asked to charge 2000 USDC, trader should be debited by that exactly and get whatever ETH it is
      expect(vBaseIn).to.eq(parseUsdc('2000'));

      const { vBaseMintEvent } = await extractEvents(vPoolWrapper.swap(true, parseUsdc('2000'), 0));
      if (!vBaseMintEvent) {
        throw new Error('vBaseMintEvent not emitted');
      }
      // swap amount excludes protocol fee, liquidity fee
      // but amount is inflated to include uniswap fees, which is ignored later
      expect(vBaseMintEvent.args.value).to.eq(
        parseUsdc('2000')
          .mul(1e6 - protocolFee - liquidityFee)
          .div(1e6 - uniswapFee),
        'mint mismatch',
      );
    });

    it('sell 1 ETH (exactIn 1 ETH)', async () => {
      const { vTokenIn } = await vPoolWrapper.callStatic.swap(false, parseEther('-1'), 0);

      // when asked to charge 1 ETH, trader should be debited by that exactly and get whatever ETH
      expect(vTokenIn).to.eq(parseEther('1'));

      const { vTokenMintEvent } = await extractEvents(vPoolWrapper.swap(false, parseEther('-1'), 0));
      if (!vTokenMintEvent) {
        throw new Error('vTokenMintEvent not emitted');
      }
      // amount is inflated, so the inflated amount is collected as fees by uniswap
      expect(vTokenMintEvent.args.value).to.eq(
        parseEther('1')
          .mul(1e6)
          .div(1e6 - uniswapFee),
      );
    });

    it('sell ETH worth 2000 USDC (exactOut 2000 USDC)', async () => {
      const { vBaseIn } = await vPoolWrapper.callStatic.swap(true, parseUsdc('-2000'), 0);
      expect(vBaseIn.mul(-1)).to.eq(parseUsdc('2000'));

      const { vBaseBurnEvent } = await extractEvents(vPoolWrapper.swap(true, parseUsdc('-2000'), 0));
      if (!vBaseBurnEvent) {
        throw new Error('vBaseMintEvent not emitted');
      }
      // amount is inflated for uniswap and protocol fee both
      expect(vBaseBurnEvent.args.value).to.eq(
        parseUsdc('2000')
          .mul(1e6 - liquidityFee - protocolFee)
          .div(1e6),
      );
    });
  });

  describe('#getValuesInside', () => {
    let protocolFee: number;
    let uniswapFee: number;

    let liquidity1: BigNumber;
    let liquidity2: BigNumber;
    beforeEach(async () => {
      // sets up the liquidity
      // -20 -> -10 ===> 100 A
      // -10 ->   0 ===> 100 A
      //   0 ->  10 ===> 100 B
      //  10 ->  20 ===> 100 B
      ({ vPoolWrapper, vPool, vBase, vToken } = await setupWrapper({
        rPriceInitial: 1,
        vPriceInitial: 1,
        vBaseDecimals: 18,
        vTokenDecimals: 18,
        liquidityFee: 0,
        protocolFee: 500,
      }));
      protocolFee = await vPoolWrapper.protocolFeePips();
      uniswapFee = await vPoolWrapper.uniswapFeePips();

      const { sqrtPriceX96 } = await vPool.slot0();
      liquidity1 = maxLiquidityForAmounts(sqrtPriceX96, -10, 10, parseUnits('100', 18), parseUnits('100', 18), true);
      liquidity2 = maxLiquidityForAmounts(sqrtPriceX96, 10, 20, parseUnits('100', 18), parseUnits('100', 18), true);

      await vPoolWrapper.liquidityChange(-10, 10, liquidity1);
      await vPoolWrapper.liquidityChange(10, 20, liquidity2);
      await vPoolWrapper.liquidityChange(-20, -10, liquidity2);
    });

    describe('fp', () => {
      it('no tick cross', async () => {
        // buy 50 VTokens, does not cross tick
        const tradeAmount = parseUnits('50', 18);
        await vPoolWrapper.swap(false, tradeAmount.mul(-1), 0);

        const globalState = await getGlobal();
        console.log(globalState);

        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumAX128).to.eq(globalState.sumAX128);
        expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);
        expect(valuesInside20.sumFpInsideX128).to.eq(globalState.sumFpX128);

        // fp values should be correct
        expect(valuesInside20.sumAX128).to.eq(0);
        expect(valuesInside20.sumBInsideX128).to.eq(tradeAmount.mul(Q128).div(liquidity1));
        expect(valuesInside20.sumFpInsideX128).to.eq(0);
      });

      it('single tick cross', async () => {
        // buy 150 VTokens, crosses a tick
        const tradeAmount = parseUnits('150', 18);
        await vPoolWrapper.swap(false, tradeAmount, 0);

        const globalState = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumAX128).to.eq(globalState.sumAX128);
        expect(valuesInside20.sumBInsideX128).to.eq(globalState.sumBX128);
        expect(valuesInside20.sumFpInsideX128).to.eq(globalState.sumFpX128);

        expect(valuesInside20.sumAX128).to.eq(0);
        expect(valuesInside20.sumBInsideX128).to.eq(
          parseUnits('100', 18)
            .sub(1)
            .mul(Q128)
            .div(liquidity1)
            .add(parseUnits('50', 18).add(1).mul(Q128).div(liquidity2)),
        );
        expect(valuesInside20.sumFpInsideX128).to.eq(0);
      });
    });

    describe('fee', () => {
      it('buy: no tick cross', async () => {
        // buy VToken worth 50 VBase, does not cross tick
        const tradeAmount = parseUnits('50', 18);
        await vPoolWrapper.swap(true, tradeAmount, 0);

        const globalState = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

        // if buy then uniswap fee will increase
        const expectedUniswapFeeIncrease = tradeAmount
          .abs()
          // removing protocol fee
          .mul(1e6 - protocolFee)
          .div(1e6)
          // calculating uniswap fee
          .mul(uniswapFee)
          .div(1e6)
          // taking per liquidity
          .mul(Q128)
          .div(liquidity1);
        const expectedFeeIncrease = 0;
        expect(valuesInside20.sumFeeInsideX128).to.eq(expectedUniswapFeeIncrease.add(expectedFeeIncrease));
      });

      it('sell: no tick cross', async () => {
        // buy VToken worth 50 VBase, does not cross tick
        const tradeAmount = parseUnits('-50', 18);
        await vPoolWrapper.swap(true, tradeAmount, 0);

        const globalState = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumFeeInsideX128).to.eq(globalState.sumFeeGlobalX128);

        // if buy then uniswap fee will increase
        const expectedUniswapFeeIncrease = BigNumber.from(0);
        const expectedFeeIncrease = tradeAmount
          .abs()
          // adjusting protocol fee and inflation
          .mul(1e6 + protocolFee)
          .div(1e6 - uniswapFee)
          // calculating uniswap fee
          .mul(uniswapFee)
          .div(1e6 - uniswapFee)
          // taking per liquidity
          .mul(Q128)
          .div(liquidity1);
        expect(valuesInside20.sumFeeInsideX128).to.eq(expectedUniswapFeeIncrease.add(expectedFeeIncrease));
      });

      it('buy: single tick cross');
      it('sell: single tick cross');
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

  async function extractEvents(tx: ContractTransaction | Promise<ContractTransaction>) {
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

  async function getGlobal(): Promise<{
    sumAX128: BigNumber;
    sumBX128: BigNumber;
    sumFpX128: BigNumber;
    timestampLast: number;
    sumFeeGlobalX128: BigNumber;
  }> {
    const fpGlobal = await vPoolWrapper.fpGlobal();
    const uniswapFeeX128 = await vPool.feeGrowthGlobal1X128();
    const sumFeeGlobalX128 = await vPoolWrapper.sumFeeGlobalX128();
    return { ...fpGlobal, sumFeeGlobalX128: uniswapFeeX128.add(sumFeeGlobalX128) };
  }

  function parseUsdc(str: string): BigNumber {
    return parseUnits(str.replaceAll(',', '').replaceAll('_', ''), 6);
  }
});
