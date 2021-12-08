import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { TickMath, maxLiquidityForAmounts as maxLiquidityForAmounts_, SqrtPriceMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';
import { VBase, VToken } from '../../typechain-types';
import { ContractOrSmock, tickToSqrtPriceX96 } from './price-tick';

export function maxLiquidityForAmounts(
  sqrtPriceCurrent: BigNumberish,
  tickLower: number,
  tickUpper: number,
  vBaseAmount: BigNumberish,
  vTokenAmount: BigNumberish,
  useFullPrecision: boolean,
  vBase: ContractOrSmock<VBase>,
  vToken: ContractOrSmock<VToken>,
) {
  sqrtPriceCurrent = BigNumber.from(sqrtPriceCurrent);
  vBaseAmount = BigNumber.from(vBaseAmount);
  vTokenAmount = BigNumber.from(vTokenAmount);
  let [amount0, amount1] = [JSBI.BigInt(vBaseAmount.toString()), JSBI.BigInt(vTokenAmount.toString())];
  if (BigNumber.from(vBase.address).gt(vToken.address)) {
    [amount0, amount1] = [amount1, amount0];
  }
  return BigNumber.from(
    maxLiquidityForAmounts_(
      JSBI.BigInt(sqrtPriceCurrent.toString()),
      TickMath.getSqrtRatioAtTick(tickLower),
      TickMath.getSqrtRatioAtTick(tickUpper),
      JSBI.BigInt(vBaseAmount.toString()),
      JSBI.BigInt(vTokenAmount.toString()),
      useFullPrecision,
    ).toString(),
  );
}

export function amountsForLiquidity(
  sqrtPriceLower: BigNumberish,
  sqrtPriceCurrent: BigNumberish,
  sqrtPriceUpper: BigNumberish,
  liquidity: BigNumberish,
  roundUp: boolean,
  vBase: ContractOrSmock<VBase>,
  vToken: ContractOrSmock<VToken>,
) {
  [sqrtPriceLower, sqrtPriceCurrent, sqrtPriceUpper] = [sqrtPriceLower, sqrtPriceCurrent, sqrtPriceUpper]
    .map(BigNumber.from)
    .sort((a, b) => {
      return a.gt(b) ? 1 : -1;
    });

  const liquidityJSBI = JSBI.BigInt(BigNumber.from(liquidity).toString());
  const sqrtPriceLowerJSBI = JSBI.BigInt(sqrtPriceLower.toString());
  const sqrtPriceUpperJSBI = JSBI.BigInt(sqrtPriceUpper.toString());
  const sqrtPriceCurrentJSBI = JSBI.BigInt(sqrtPriceCurrent.toString());

  let amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentJSBI, sqrtPriceLowerJSBI, liquidityJSBI, roundUp);
  let amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentJSBI, sqrtPriceUpperJSBI, liquidityJSBI, roundUp);
  if (BigNumber.from(vBase.address).gt(vToken.address)) {
    [amount0, amount1] = [amount1, amount0];
  }

  return {
    vBaseAmount: BigNumber.from(amount0.toString()),
    vTokenAmount: BigNumber.from(amount1.toString()),
  };
}
