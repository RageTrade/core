import { FakeContract, MockContract } from '@defi-wonderland/smock';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { Contract } from '@ethersproject/contracts';
import { TickMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';
import { VQuote, VToken } from '../../typechain-types';
import { fromQ128, fromQ96, Q96, toQ128, toQ96 } from './fixed-point';
import hre from 'hardhat';

export declare type ERC20Decimals = { decimals(): Promise<number> } | string | number; // C | MockContract<C> | FakeContract<C>;

async function getDecimals(contractOrValue: ERC20Decimals) {
  if (typeof contractOrValue === 'number') {
    return contractOrValue;
  } else if (typeof contractOrValue === 'string') {
    return (await hre.ethers.getContractAt('ERC20', contractOrValue)).decimals();
  } else {
    return await contractOrValue.decimals();
  }
}

const tickSpacing = 10;

export async function priceToTick(
  price: number,
  vQuote: ERC20Decimals,
  vToken: ERC20Decimals,
  roundToNearestInitializableTick?: boolean,
): Promise<number> {
  const vQuoteDecimals = await getDecimals(vQuote);
  const vTokenDecimals = await getDecimals(vToken);
  price *= 10 ** (vQuoteDecimals - vTokenDecimals);

  return sqrtPriceX96ToTick(toQ96(Math.sqrt(price)), roundToNearestInitializableTick);
}

export function sqrtPriceX96ToTick(sqrtPriceX96: BigNumberish, roundToNearestInitializableTick?: boolean): number {
  sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
  const tick = TickMath.getTickAtSqrtRatio(JSBI.BigInt(sqrtPriceX96.toHexString()));
  if (roundToNearestInitializableTick) {
    return tickToNearestInitializableTick(tick);
  } else {
    return tick;
  }
}

export function tickToNearestInitializableTick(tick: number): number {
  const tickRoundedDown = Math.floor(tick / tickSpacing) * tickSpacing;
  const roundUp = tick % tickSpacing >= tickSpacing / 2;
  return roundUp ? tickRoundedDown + tickSpacing : tickRoundedDown;
}

export function tickToSqrtPriceX96(tick: number): BigNumber {
  const sqrtPriceX96 = BigNumber.from(TickMath.getSqrtRatioAtTick(tick).toString());
  return sqrtPriceX96;
}

export async function tickToPrice(tick: number, vQuote: ERC20Decimals, vToken: ERC20Decimals): Promise<number> {
  let price = fromQ96(tickToSqrtPriceX96(tick)) ** 2;
  const vQuoteDecimals = await getDecimals(vQuote);
  const vTokenDecimals = await getDecimals(vToken);
  price /= 10 ** (vQuoteDecimals - vTokenDecimals);
  return price;
}

/**
 * Parses human readable prices to fixed point 128
 * and also applies the decimals.
 * @param price Human readable price
 * @param vQuote VQuote contract for quering decimals
 * @param vToken VToken contract for quering decimals
 * @returns fixed point 128 and decimals applied price
 */
export async function priceToPriceX128(
  price: number,
  vQuote: ERC20Decimals,
  vToken: ERC20Decimals,
): Promise<BigNumber> {
  const vQuoteDecimals = await getDecimals(vQuote);
  const vTokenDecimals = await getDecimals(vToken);
  let priceX128 = toQ128(price);
  priceX128 = priceX128.mul(BigNumber.from(10).pow(vQuoteDecimals)).div(BigNumber.from(10).pow(vTokenDecimals));
  return priceX128;
}

/**
 * Formats the fixed point price into human readable
 * @param priceX128 fixed point 128 and decimals applied price
 * @param vQuote VQuote contract for quering decimals
 * @param vToken VToken contract for quering decimals
 * @returns human readable price
 */
export async function priceX128ToPrice(
  priceX128: BigNumberish,
  vQuote: ERC20Decimals,
  vToken: ERC20Decimals,
): Promise<number> {
  priceX128 = BigNumber.from(priceX128);
  let price: number = fromQ128(priceX128);
  const vQuoteDecimals = await getDecimals(vQuote);
  const vTokenDecimals = await getDecimals(vToken);
  price /= 10 ** (vQuoteDecimals - vTokenDecimals);
  return price;
}

/**
 * Converts priceX128 (vQuote per vToken) into sqrtPriceX96 (token1 per token0)
 * @param priceX128 fixed point 128 and decimals applied price
 * @param vQuote VQuote contract determining the token0-token1
 * @param vToken VToken contract determining the token0-token1
 * @returns sqrtPriceX96 for use in uniswap
 */
export function priceX128ToSqrtPriceX96(priceX128: BigNumberish): BigNumber {
  priceX128 = BigNumber.from(priceX128);
  const sqrtPriceX96 = sqrt(priceX128.mul(1n << 64n)); // 96 = (128 + 64) / 2
  return sqrtPriceX96;
}

export function sqrtPriceX96ToPriceX128(sqrtPriceX96: BigNumberish): BigNumber {
  sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
  const priceX128 = sqrtPriceX96.mul(sqrtPriceX96).div(1n << 64n);
  return priceX128;
}

export async function priceToSqrtPriceX96(price: number, vQuote: ERC20Decimals, vToken: ERC20Decimals) {
  let priceX128 = await priceToPriceX128(price, vQuote, vToken);
  return priceX128ToSqrtPriceX96(priceX128);
}

// export async function priceToSqrtPriceX96WithoutContract(
//   price: number,
//   vQuoteDecimals: BigNumberish,
//   vTokenDecimals: BigNumberish,
// ) {
//   let priceX128 = toQ128(price);
//   priceX128 = priceX128.mul(BigNumber.from(10).pow(vQuoteDecimals)).div(BigNumber.from(10).pow(vTokenDecimals));
//   priceX128 = BigNumber.from(priceX128);

//   let sqrtPriceX96 = sqrt(priceX128.mul(1n << 64n)); // 96 = (128 + 64) / 2
//   return sqrtPriceX96;
// }

export async function sqrtPriceX96ToPrice(sqrtPriceX96: BigNumberish, vQuote: ERC20Decimals, vToken: ERC20Decimals) {
  const priceX128 = sqrtPriceX96ToPriceX128(sqrtPriceX96);
  return priceX128ToPrice(priceX128, vQuote, vToken);
}

export async function priceToSqrtPriceX96WithoutContract(
  price: number,
  vQuoteDecimals: BigNumberish,
  vTokenDecimals: BigNumberish,
  isToken0: boolean,
) {
  let priceX128 = toQ128(price);

  priceX128 = priceX128.mul(BigNumber.from(10).pow(vQuoteDecimals)).div(BigNumber.from(10).pow(vTokenDecimals));
  priceX128 = BigNumber.from(priceX128);
  let sqrtPriceX96 = sqrt(priceX128.mul(1n << 64n)); // 96 = (128 + 64) / 2

  if (isToken0) {
    sqrtPriceX96 = Q96.mul(Q96).div(sqrtPriceX96);
  }
  return sqrtPriceX96;
}

export function initializableTick(tick: number, tickSpacing: number) {
  return Math.floor(tick / tickSpacing) * tickSpacing;
}

export async function priceToNearestPriceX128(
  price: number,
  vQuote: ERC20Decimals,
  vToken: ERC20Decimals,
): Promise<BigNumber> {
  return sqrtPriceX96ToPriceX128(tickToSqrtPriceX96(await priceToTick(price, vQuote, vToken)));
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
