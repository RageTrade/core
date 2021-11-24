import { BigNumber, BigNumberish, FixedNumber } from '@ethersproject/bignumber';
import hre, { ethers } from 'hardhat';
import { VPoolWrapper, VPoolFactory, ERC20, VBase, VToken, UniswapV3Pool, ERC20__factory } from '../typechain-types';
import { ERC20Interface } from '../typechain-types/ERC20';
import { Q128, Q96, toQ96 } from './utils/fixed-point';
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
  let vPoolWrapper: VPoolWrapper;
  let vPool: UniswapV3Pool;
  let vBase: MockContract<VBase>;
  let vToken: MockContract<VToken>;

  let isToken0: boolean;
  let SQRT_RATIO_LOWER_LIMIT: BigNumberish;
  let SQRT_RATIO_UPPER_LIMIT: BigNumberish;

  describe('#liquidityChange', () => {
    before(async () => {
      ({ vPoolWrapper, vPool, isToken0, vBase, vToken } = await setupWrapper({
        rPriceInitial: 1,
        vPriceInitial: 1,
      }));
    });

    it('adds liquidity', async () => {
      const { tick } = await vPool.slot0();
      await vPoolWrapper.liquidityChange(
        initializableTick(tick - 100, 10),
        initializableTick(tick + 100, 10),
        10_000_000,
      );
      expect(await vPool.liquidity()).to.eq(10_000_000);
    });

    it('removes liquidity', async () => {
      const { tick } = await vPool.slot0();
      await vPoolWrapper.liquidityChange(
        initializableTick(tick - 100, 10),
        initializableTick(tick + 100, 10),
        -4_000_000,
      );
      expect(await vPool.liquidity()).to.eq(6_000_000);
    });
  });

  describe('#swap', () => {
    let protocolFee: number;
    let uniswapFee: number;

    before(async () => {
      ({ vPoolWrapper, vPool, isToken0, vBase, vToken } = await setupWrapper({
        rPriceInitial: 2000,
        vPriceInitial: 2000,
      }));

      protocolFee = await vPoolWrapper.protocolFee();
      uniswapFee = await vPoolWrapper.uniswapFee();
      // const { tick, sqrtPriceX96 } = await vPool.slot0();
      // console.log({ isToken0, tick, sqrtPriceX96 });

      // bootstraping initial liquidity
      await liquidityChange(1000, 2000, 10n ** 15n); // here usdc should be put
      await liquidityChange(2000, 3000, 10n ** 15n); // here vtoken should be put
      await liquidityChange(3000, 4000, 10n ** 15n); // here vtoken should be put
      await liquidityChange(4000, 5000, 10n ** 15n);
      await liquidityChange(1000, 4000, 10n ** 15n); // here vtoken should be put

      SQRT_RATIO_LOWER_LIMIT = await priceToSqrtPriceX96(1000, vBase, vToken);
      SQRT_RATIO_UPPER_LIMIT = await priceToSqrtPriceX96(5000, vBase, vToken);
    });

    it('buy 1 ETH', async () => {
      const { vTokenIn } = await vPoolWrapper.callStatic.swap(true, parseEther('1'), 0);
      expect(vTokenIn.mul(-1)).to.eq(parseEther('1'));

      const { vTokenBurnEvent } = await extractEvents(vPoolWrapper.swap(true, parseEther('1'), 0));
      if (!vTokenBurnEvent) {
        throw new Error('vTokenBurnEvent not emitted');
      }

      expect(vTokenBurnEvent.args.value).to.eq(parseEther('1'));
    });

    it('buy ETH worth 2000 USDC', async () => {
      const { vBaseIn } = await vPoolWrapper.callStatic.swap(true, parseUsdc('-2000'), 0);
      expect(vBaseIn).to.eq(parseUsdc('2000'));

      const { vBaseMintEvent } = await extractEvents(vPoolWrapper.swap(true, parseUsdc('-2000'), 0));
      if (!vBaseMintEvent) {
        throw new Error('vBaseMintEvent not emitted');
      }

      // protocol fee is collected in vBase already
      expect(vBaseMintEvent.args.value).to.eq(
        parseUsdc('2000')
          .mul(1e6 - protocolFee)
          .div(1e6),
      );
    });

    it('sell 1 ETH', async () => {
      const { vTokenIn } = await vPoolWrapper.callStatic.swap(false, parseEther('1'), 0);
      expect(vTokenIn).to.eq(parseEther('1'));

      const { vTokenMintEvent } = await extractEvents(vPoolWrapper.swap(false, parseEther('1'), 0));
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

    it('sell ETH worth 2000 USDC', async () => {
      const { vBaseIn } = await vPoolWrapper.callStatic.swap(false, parseUsdc('-2000'), 0);
      expect(vBaseIn.mul(-1)).to.eq(parseUsdc('2000'));

      const { vBaseBurnEvent } = await extractEvents(vPoolWrapper.swap(false, parseUsdc('-2000'), 0));
      if (!vBaseBurnEvent) {
        throw new Error('vBaseMintEvent not emitted');
      }
      // amount is inflated for uniswap and protocol fee both
      expect(vBaseBurnEvent.args.value).to.eq(
        parseUsdc('2000')
          .mul(1e6)
          .div(1e6 - uniswapFee)
          .mul(1e6 + protocolFee)
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
      ({ vPoolWrapper, vPool, isToken0, vBase, vToken } = await setupWrapper({
        rPriceInitial: 1,
        vPriceInitial: 1,
        vBaseDecimals: 18,
        vTokenDecimals: 18,
        extendedFee: 0,
        protocolFee: 500,
      }));
      protocolFee = await vPoolWrapper.protocolFee();
      uniswapFee = await vPoolWrapper.uniswapFee();

      const { sqrtPriceX96 } = await vPool.slot0();
      liquidity1 = maxLiquidityForAmounts(
        sqrtPriceX96,
        -10,
        10,
        parseUnits('100', 18),
        parseUnits('100', 18),
        true,
        vBase,
        vToken,
      );
      liquidity2 = maxLiquidityForAmounts(
        sqrtPriceX96,
        10,
        20,
        parseUnits('100', 18),
        parseUnits('100', 18),
        true,
        vBase,
        vToken,
      );

      await vPoolWrapper.liquidityChange(-10, 10, liquidity1);
      await vPoolWrapper.liquidityChange(10, 20, liquidity2);
      await vPoolWrapper.liquidityChange(-20, -10, liquidity2);
    });

    describe('fp', () => {
      it('no tick cross', async () => {
        // buy 50 VTokens, does not cross tick
        const tradeAmount = parseUnits('50', 18);
        await vPoolWrapper.swap(true, tradeAmount, 0);

        const global = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumAX128).to.eq(global.sumAX128);
        expect(valuesInside20.sumBInsideX128).to.eq(global.sumBX128);
        expect(valuesInside20.sumFpInsideX128).to.eq(global.sumFpX128);

        // fp values should be correct
        expect(valuesInside20.sumAX128).to.eq(0);
        expect(valuesInside20.sumBInsideX128).to.eq(tradeAmount.mul(Q128).div(liquidity1));
        expect(valuesInside20.sumFpInsideX128).to.eq(0);
      });

      it('single tick cross', async () => {
        // buy 150 VTokens, crosses a tick
        const tradeAmount = parseUnits('150', 18);
        await vPoolWrapper.swap(true, tradeAmount, 0);

        const global = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.sumAX128).to.eq(global.sumAX128);
        expect(valuesInside20.sumBInsideX128).to.eq(global.sumBX128);
        expect(valuesInside20.sumFpInsideX128).to.eq(global.sumFpX128);

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
        const tradeAmount = parseUnits('-50', 18);
        await vPoolWrapper.swap(true, tradeAmount, 0);

        const global = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.uniswapFeeInsideX128).to.eq(global.uniswapFeeX128);
        expect(valuesInside20.extendedFeeInsideX128).to.eq(global.extendedFeeX128);

        // if buy then uniswap fee will increase
        expect(valuesInside20.uniswapFeeInsideX128).to.eq(
          tradeAmount
            .abs()
            // removing protocol fee
            .mul(1e6 - protocolFee)
            .div(1e6)
            // calculating uniswap fee
            .mul(uniswapFee)
            .div(1e6)
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1),
        );
        expect(valuesInside20.extendedFeeInsideX128).to.eq(0);
      });

      it('sell: no tick cross', async () => {
        // buy VToken worth 50 VBase, does not cross tick
        const tradeAmount = parseUnits('-50', 18);
        await vPoolWrapper.swap(false, tradeAmount, 0);

        const global = await getGlobal();
        const valuesInside20 = await vPoolWrapper.getValuesInside(-20, 20);

        // since no trades went outside -20 and 20, values inside should be same as global
        expect(valuesInside20.uniswapFeeInsideX128).to.eq(global.uniswapFeeX128);
        expect(valuesInside20.extendedFeeInsideX128).to.eq(global.extendedFeeX128);

        // if buy then uniswap fee will increase
        expect(valuesInside20.uniswapFeeInsideX128).to.eq(0);

        expect(valuesInside20.extendedFeeInsideX128).to.eq(
          tradeAmount
            .abs()
            // adjusting protocol fee and inflation
            .mul(1e6 + protocolFee)
            .div(1e6 - uniswapFee)
            // calculating uniswap fee
            .mul(uniswapFee)
            .div(1e6 - uniswapFee)
            // taking per liquidity
            .mul(Q128)
            .div(liquidity1),
        );
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

    if (!isToken0) {
      [tickLower, tickUpper] = [tickUpper, tickLower];
    }
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
    uniswapFeeX128: BigNumber;
    extendedFeeX128: BigNumber;
  }> {
    const fpGlobal = await vPoolWrapper.fpGlobal();
    const uniswapFeeX128 = isToken0 ? await vPool.feeGrowthGlobal1X128() : await vPool.feeGrowthGlobal0X128();
    const extendedFeeX128 = await vPoolWrapper.extendedFeeGrowthGlobalX128();
    return { ...fpGlobal, uniswapFeeX128, extendedFeeX128 };
  }

  function parseUsdc(str: string): BigNumber {
    return parseUnits(str.replaceAll(',', '').replaceAll('_', ''), 6);
  }
});
