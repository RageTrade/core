import { MockContract } from '@defi-wonderland/smock';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { TickMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';
import { VBase, VToken } from '../../typechain-types';
import { fromQ128, fromQ96, Q96, toQ128, toQ96 } from './fixed-point';

export async function priceToTick(
  price: number,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): Promise<number> {
  // console.log('price', price);
  const vBaseDecimals = await vBase.decimals();
  const vTokenDecimals = await vToken.decimals();
  price *= 10 ** (vBaseDecimals - vTokenDecimals);
  if (!BigNumber.from(vBase.address).gt(vToken.address)) {
    price = 1 / price;
  }

  const tick = TickMath.getTickAtSqrtRatio(JSBI.BigInt(toQ96(Math.sqrt(price)).toHexString()));
  // console.log('tick', tick);
  return tick;
}

export async function sqrtPriceX96ToTick(sqrtPriceX96: BigNumberish): Promise<number> {
  sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
  const tick = TickMath.getTickAtSqrtRatio(JSBI.BigInt(sqrtPriceX96.toHexString()));
  return tick;
}

export async function tickToPrice(
  tick: number,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): Promise<number> {
  let price = fromQ96(BigNumber.from(TickMath.getSqrtRatioAtTick(tick).toString())) ** 2;
  if (!BigNumber.from(vBase.address).gt(vToken.address)) {
    price = 1 / price;
  }
  const vBaseDecimals = await vBase.decimals();
  const vTokenDecimals = await vToken.decimals();
  price /= 10 ** (vBaseDecimals - vTokenDecimals);
  return price;
}
export async function tickToSqrtPriceX96(tick: number): Promise<BigNumber> {
  let sqrtPriceX96 = BigNumber.from(TickMath.getSqrtRatioAtTick(tick).toString());
  return sqrtPriceX96;
}

/**
 * Parses human readable prices to fixed point 128
 * and also applies the decimals.
 * @param price Human readable price
 * @param vBase VBase contract for quering decimals
 * @param vToken VToken contract for quering decimals
 * @returns fixed point 128 and decimals applied price
 */
export async function priceToPriceX128(
  price: number,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): Promise<BigNumber> {
  const vBaseDecimals = await vBase.decimals();
  const vTokenDecimals = await vToken.decimals();

  let priceX128 = toQ128(price);
  priceX128 = priceX128.mul(BigNumber.from(10).pow(vBaseDecimals)).div(BigNumber.from(10).pow(vTokenDecimals));
  // if (!BigNumber.from(vBase.address).gt(vToken.address)) {
  //   price = 1 / price;
  // }
  return priceX128;
}

/**
 * Formats the fixed point price into human readable
 * @param priceX128 fixed point 128 and decimals applied price
 * @param vBase VBase contract for quering decimals
 * @param vToken VToken contract for quering decimals
 * @returns human readable price
 */
export async function priceX128ToPrice(
  priceX128: BigNumberish,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): Promise<number> {
  priceX128 = BigNumber.from(priceX128);
  let price: number = fromQ128(priceX128);
  // if (!BigNumber.from(vBase.address).gt(vToken.address)) {
  //   price = 1 / fromQ128(priceX128);
  // }
  const vBaseDecimals = await vBase.decimals();
  const vTokenDecimals = await vToken.decimals();
  price /= 10 ** (vBaseDecimals - vTokenDecimals);
  return price;
}

/**
 * Converts priceX128 (vBase per vToken) into sqrtPriceX96 (token1 per token0)
 * @param priceX128 fixed point 128 and decimals applied price
 * @param vBase VBase contract determining the token0-token1
 * @param vToken VToken contract determining the token0-token1
 * @returns sqrtPriceX96 for use in uniswap
 */
export function priceX128ToSqrtPriceX96(
  priceX128: BigNumberish,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): BigNumber {
  priceX128 = BigNumber.from(priceX128);
  let sqrtPriceX96 = sqrt(priceX128.mul(1n << 64n)); // 96 = (128 + 64) / 2

  if (!BigNumber.from(vBase.address).gt(vToken.address)) {
    sqrtPriceX96 = Q96.mul(Q96).div(sqrtPriceX96);
  }
  return sqrtPriceX96;
}

export function sqrtPriceX96ToPriceX128(
  sqrtPriceX96: BigNumberish,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
): BigNumber {
  sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
  if (!BigNumber.from(vBase.address).gt(vToken.address)) {
    sqrtPriceX96 = Q96.mul(Q96).div(sqrtPriceX96);
  }
  let priceX128 = sqrtPriceX96.mul(sqrtPriceX96).div(Q96);
  return priceX128;
}

export async function priceToSqrtPriceX96(
  price: number,
  vBase: VBase | MockContract<VBase>,
  vToken: VToken | MockContract<VToken>,
) {
  let priceX128 = await priceToPriceX128(price, vBase, vToken);
  return priceX128ToSqrtPriceX96(priceX128, vBase, vToken);
}

const ONE = BigNumber.from(1);
const TWO = BigNumber.from(2);

function sqrt(value: BigNumberish) {
  const x = BigNumber.from(value);
  let z = x.add(ONE).div(TWO);
  let y = x;
  while (z.sub(y).isNegative()) {
    y = z;
    z = x.div(z).add(z).div(TWO);
  }
  return y;
}
