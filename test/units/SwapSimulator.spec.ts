import { expect } from 'chai';
import { BigNumber, BigNumberish } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import hre from 'hardhat';

import { MockContract } from '@defi-wonderland/smock';
import { parseUsdc, priceToTick } from '@ragetrade/sdk';

import { SwapSimulator, UniswapV3Pool, VPoolWrapperMock2, VQuote, VToken } from '../../typechain-types';
import { setupWrapper } from '../helpers/setup-wrapper';

describe('SwapSimulator', () => {
  let vPoolWrapper: MockContract<VPoolWrapperMock2>;
  let vPool: UniswapV3Pool;
  let vQuote: MockContract<VQuote>;
  let vToken: MockContract<VToken>;
  let swapSimulator: SwapSimulator;

  const liquidityFee = 900;
  const protocolFee = 300;

  before(async () => {
    ({ vPoolWrapper, vPool, vQuote, vToken } = await setupWrapper({
      rPriceInitial: 2000,
      vPriceInitial: 2000,
      liquidityFee,
      protocolFee,
      vQuoteDecimals: 6,
      vTokenDecimals: 18,
    }));

    swapSimulator = await (await hre.ethers.getContractFactory('SwapSimulator')).deploy();

    expect(await vPoolWrapper.liquidityFeePips()).to.eq(liquidityFee);
    expect(await vPoolWrapper.protocolFeePips()).to.eq(protocolFee);

    await liquidityChange(1000, 4000, 10n ** 16n); // here vtoken should be put
  });

  const SWAP = {
    VTOKEN_FOR_VQUOTE: true,
    VQUOTE_FOR_VTOKEN: false,
  };

  it('exactIn 1 ETH', async () => {
    const amountSpecified = parseEther('1');
    const swapDirection = SWAP.VTOKEN_FOR_VQUOTE;

    const vPoolWrapperSwapResult = await vPoolWrapper.callStatic.swap(swapDirection, amountSpecified, 0);
    const { swapResult: simulatorSwapResult } = await swapSimulator.callStatic.simulateSwapOnVPool(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );
    const simulatorSwapViewResult = await swapSimulator.simulateSwapOnVPoolView(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );

    expect(simulatorSwapResult).to.deep.eq(vPoolWrapperSwapResult);

    expect(simulatorSwapViewResult.vTokenIn).to.eq(vPoolWrapperSwapResult.vTokenIn);
    expect(simulatorSwapViewResult.vQuoteIn).to.eq(vPoolWrapperSwapResult.vQuoteIn);

    // when asked to charge 1 ETH, trader should be debited by that exactly and get whatever ETH
    expect(simulatorSwapResult.vTokenIn).to.eq(parseEther('1'));
  });

  it('exactIn 2000 USDC', async () => {
    const amountSpecified = parseUsdc('2000');
    const swapDirection = SWAP.VQUOTE_FOR_VTOKEN;

    const vPoolWrapperSwapResult = await vPoolWrapper.callStatic.swap(swapDirection, amountSpecified, 0);
    const { swapResult: simulatorSwapResult } = await swapSimulator.callStatic.simulateSwapOnVPool(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );
    const simulatorSwapViewResult = await swapSimulator.simulateSwapOnVPoolView(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );

    expect(simulatorSwapResult).to.deep.eq(vPoolWrapperSwapResult);

    expect(simulatorSwapViewResult.vTokenIn).to.eq(vPoolWrapperSwapResult.vTokenIn);
    expect(simulatorSwapViewResult.vQuoteIn).to.eq(vPoolWrapperSwapResult.vQuoteIn);

    // when asked to charge 2000 USDC, trader should be debited by that exactly and get whatever ETH it is
    expect(simulatorSwapResult.vQuoteIn).to.eq(parseUsdc('2000'));
  });

  it('exactOut 1 ETH', async () => {
    const amountSpecified = parseEther('-1');
    const swapDirection = SWAP.VQUOTE_FOR_VTOKEN;

    const vPoolWrapperSwapResult = await vPoolWrapper.callStatic.swap(swapDirection, amountSpecified, 0);
    const { swapResult: simulatorSwapResult } = await swapSimulator.callStatic.simulateSwapOnVPool(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );
    const simulatorSwapViewResult = await swapSimulator.simulateSwapOnVPoolView(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );

    expect(simulatorSwapResult).to.deep.eq(vPoolWrapperSwapResult);

    expect(simulatorSwapViewResult.vTokenIn).to.eq(vPoolWrapperSwapResult.vTokenIn);
    expect(simulatorSwapViewResult.vQuoteIn).to.eq(vPoolWrapperSwapResult.vQuoteIn);

    // when asked for 1 ETH output, trader should get that exactly and be charged whatever USDC it is
    expect(simulatorSwapResult.vTokenIn.isNegative()).to.be.true;
    expect(simulatorSwapResult.vTokenIn.mul(-1)).to.eq(parseEther('1'));
  });

  it('exactOut 2000 USDC', async () => {
    const amountSpecified = parseUsdc('-2000');
    const swapDirection = SWAP.VTOKEN_FOR_VQUOTE;

    const vPoolWrapperSwapResult = await vPoolWrapper.callStatic.swap(swapDirection, amountSpecified, 0);
    const { swapResult: simulatorSwapResult } = await swapSimulator.callStatic.simulateSwapOnVPool(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );
    const simulatorSwapViewResult = await swapSimulator.simulateSwapOnVPoolView(
      vPool.address,
      liquidityFee,
      protocolFee,
      swapDirection,
      amountSpecified,
      0,
    );

    expect(simulatorSwapResult).to.deep.eq(vPoolWrapperSwapResult);

    expect(simulatorSwapViewResult.vTokenIn).to.eq(vPoolWrapperSwapResult.vTokenIn);
    expect(simulatorSwapViewResult.vQuoteIn).to.eq(vPoolWrapperSwapResult.vQuoteIn);

    expect(simulatorSwapResult.vQuoteIn.isNegative()).to.be.true;
    expect(simulatorSwapResult.vQuoteIn.mul(-1)).to.eq(parseUsdc('2000'));
  });

  async function liquidityChange(priceLower: number, priceUpper: number, liquidityDelta: BigNumberish) {
    const tickSpacing = await vPool.tickSpacing();
    let tickLower = await priceToTick(priceLower, vQuote, vToken);
    let tickUpper = await priceToTick(priceUpper, vQuote, vToken);
    tickLower -= tickLower % tickSpacing;
    tickUpper -= tickUpper % tickSpacing;

    if (!BigNumber.from(liquidityDelta).isNegative()) {
      await vPoolWrapper.mint(tickLower, tickUpper, liquidityDelta);
    } else {
      await vPoolWrapper.burn(tickLower, tickUpper, liquidityDelta);
    }
  }
});
