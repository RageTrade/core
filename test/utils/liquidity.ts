import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { TickMath, maxLiquidityForAmounts as maxLiquidityForAmounts_, SqrtPriceMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';
import { VBase, VToken } from '../../typechain-types';
import { tickToSqrtPriceX96, ERC20Decimals } from './price-tick';

export function maxLiquidityForAmounts(
  sqrtPriceCurrent: BigNumberish,
  tickLower: number,
  tickUpper: number,
  vBaseAmount: BigNumberish,
  vTokenAmount: BigNumberish,
  useFullPrecision: boolean,
) {
  sqrtPriceCurrent = BigNumber.from(sqrtPriceCurrent);
  vBaseAmount = BigNumber.from(vBaseAmount);
  vTokenAmount = BigNumber.from(vTokenAmount);
  let [amount0, amount1] = [JSBI.BigInt(vTokenAmount.toString()), JSBI.BigInt(vBaseAmount.toString())];

  return BigNumber.from(
    maxLiquidityForAmounts_(
      JSBI.BigInt(sqrtPriceCurrent.toString()),
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      JSBI.BigInt(amount0.toString()),
      JSBI.BigInt(amount1.toString()),
      useFullPrecision,
    ).toString(),
  );
}

export function amountsForLiquidity(
  tickLower: number,
  sqrtPriceCurrent: BigNumberish,
  tickUpper: number,
  liquidity: BigNumberish,
) {
  let roundUp = false;
  // TODO: uncomment this and fix rounding issues
  if (liquidity > 0) roundUp = true;
  const liquidityJSBI = JSBI.BigInt(BigNumber.from(liquidity).toString());
  const sqrtPriceLowerJSBI = TickMath.getSqrtRatioAtTick(tickLower);
  const sqrtPriceUpperJSBI = TickMath.getSqrtRatioAtTick(tickUpper);
  const sqrtPriceCurrentJSBI = JSBI.BigInt(sqrtPriceCurrent.toString());
  let sqrtPriceMiddleJSBI = sqrtPriceCurrentJSBI;
  if (sqrtPriceMiddleJSBI < sqrtPriceLowerJSBI) {
    sqrtPriceMiddleJSBI = sqrtPriceLowerJSBI;
  } else if (sqrtPriceMiddleJSBI > sqrtPriceUpperJSBI) {
    sqrtPriceMiddleJSBI = sqrtPriceUpperJSBI;
  }

  let amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceMiddleJSBI, sqrtPriceUpperJSBI, liquidityJSBI, roundUp);
  let amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceLowerJSBI, sqrtPriceMiddleJSBI, liquidityJSBI, roundUp);

  let vTokenAmount = amount0;
  let vBaseAmount = amount1;

  return {
    vBaseAmount: BigNumber.from(vBaseAmount.toString()),
    vTokenAmount: BigNumber.from(vTokenAmount.toString()),
  };
}
