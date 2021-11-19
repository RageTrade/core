import { BigNumber, BigNumberish, FixedNumber } from '@ethersproject/bignumber';
import hre, { ethers } from 'hardhat';
import { VPoolWrapper, VPoolFactory, ERC20, VBase, VToken, UniswapV3Pool } from '../typechain-types';
import { Q96, toQ96 } from './utils/fixed-point';
import { formatEther, formatUnits, parseEther, parseUnits } from '@ethersproject/units';
import { priceToSqrtPriceX96, priceToTick, tickToPrice } from './utils/price-tick';
import { setupWrapper } from './utils/setup-wrapper';
import { MockContract } from '@defi-wonderland/smock';
import { TickMath } from '@uniswap/v3-sdk';
import { expect } from 'chai';

describe('PoolWrapper', () => {
  let vPoolWrapper: VPoolWrapper;
  let vPool: UniswapV3Pool;
  let vBase: MockContract<VBase>;
  let vToken: MockContract<VToken>;

  let isToken0: boolean;
  let SQRT_RATIO_LOWER_LIMIT: BigNumberish;
  let SQRT_RATIO_UPPER_LIMIT: BigNumberish;

  before(async () => {
    ({ vPoolWrapper, vPool, isToken0, vBase, vToken } = await setupWrapper({
      rPriceInitial: 2000,
      vPriceInitial: 2000,
    }));
    // const { tick } = await vPool.slot0();
    // console.log({ isToken0, tick });

    await liquidityChange(1000, 2000, 10n ** 15n); // here usdc should be put
    await liquidityChange(2000, 3000, 10n ** 30n); // here vtoken should be put
    await liquidityChange(3000, 4000, 10n ** 15n); // here vtoken should be put
    await liquidityChange(4000, 5000, 10n ** 15n);
    await liquidityChange(1000, 4000, 10n ** 15n); // here vtoken should be put

    SQRT_RATIO_LOWER_LIMIT = await priceToSqrtPriceX96(1000, vBase, vToken);
    SQRT_RATIO_UPPER_LIMIT = await priceToSqrtPriceX96(5000, vBase, vToken);
  });

  const testCases: Array<{
    buyVToken: boolean;
    amountSpecified: BigNumber;
  }> = [
    {
      buyVToken: true,
      amountSpecified: parseEther('1'),
    },
    {
      buyVToken: true,
      amountSpecified: parseUsdc('2000').mul(-1),
    },
    {
      buyVToken: false,
      amountSpecified: parseEther('1'),
    },
    {
      buyVToken: false,
      amountSpecified: parseUsdc('2000').mul(-1),
    },
  ];

  describe('#swap', () => {
    for (const { buyVToken, amountSpecified } of testCases) {
      it(`${buyVToken ? 'buy' : 'sell'} ${
        amountSpecified.gt(0)
          ? formatEther(amountSpecified) + ` ETH`
          : `ETH worth ${formatUnits(amountSpecified.mul(-1), 6)} USDC`
      }`, async () => {
        const { vBaseIn, vTokenIn } = await vPoolWrapper.callStatic.swap(
          buyVToken,
          amountSpecified,
          buyVToken != isToken0 ? BigNumber.from(SQRT_RATIO_UPPER_LIMIT) : BigNumber.from(SQRT_RATIO_LOWER_LIMIT),
        );
        // await vPoolWrapper.swap(
        //   buyVToken,
        //   amountSpecified,
        //   buyVToken != isToken0 ? BigNumber.from(SQRT_RATIO_UPPER_LIMIT) : BigNumber.from(SQRT_RATIO_LOWER_LIMIT),
        // );
        // console.log('vBaseIn, vTokenIn', formatUnits(vBaseIn, 6), formatEther(vTokenIn));

        if (amountSpecified.gt(0)) {
          expect(amountSpecified).to.eq(vTokenIn.mul(buyVToken ? -1 : 1));
        } else {
          expect(amountSpecified).to.eq(vBaseIn.mul(buyVToken ? -1 : 1));
        }
        // TODO add more checks
      });
    }
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

  function parseUsdc(str: string): BigNumber {
    return parseUnits(str.replaceAll(',', '').replaceAll('_', ''), 6);
  }
});
