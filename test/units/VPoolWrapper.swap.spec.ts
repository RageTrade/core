import hre from 'hardhat';
import { expect } from 'chai';
import { MockContract } from '@defi-wonderland/smock';
import { parseEther, parseUnits, formatEther, formatUnits } from 'ethers/lib/utils';
import { SimulateSwapTest, UniswapV3Pool, VQuote, VPoolWrapperMock2, VToken } from '../../typechain-types';
import { setupWrapper } from '../helpers/setup-wrapper';
import { tickToPrice } from '../helpers/price-tick';
import { BigNumber, BigNumberish, ContractTransaction, ethers } from 'ethers';
import { TransferEvent } from '../../typechain-types/artifacts/@openzeppelin/contracts/token/ERC20/IERC20';
import { priceToTick } from '../helpers/price-tick';
import assert from 'assert';

describe('VPoolWrapper.swap', () => {
  let vPoolWrapper: MockContract<VPoolWrapperMock2>;
  let vPool: UniswapV3Pool;
  let vQuote: MockContract<VQuote>;
  let vToken: MockContract<VToken>;

  // TODO: fuzz various liquidity and protocol fees
  const uniswapFee = 500;
  const liquidityFee = 900;
  const protocolFee = 300;
  let simulator: SimulateSwapTest;

  beforeEach(async () => {
    ({ vPoolWrapper, vPool, vQuote, vToken } = await setupWrapper({
      rPriceInitial: 2000,
      vPriceInitial: 2000,
      liquidityFee,
      protocolFee,
      vQuoteDecimals: 6,
      vTokenDecimals: 18,
    }));

    simulator = await (await hre.ethers.getContractFactory('SimulateSwapTest')).deploy(vPool.address);

    expect(await vPoolWrapper.liquidityFeePips()).to.eq(liquidityFee);
    expect(await vPoolWrapper.protocolFeePips()).to.eq(protocolFee);

    // const { tick, sqrtPriceX96 } = await vPool.slot0();

    // bootstraping initial liquidity
    // await liquidityChange(1000, 2000, 10n ** 15n); // here usdc should be put
    // await liquidityChange(2000, 3000, 10n ** 15n); // here vtoken should be put
    // await liquidityChange(3000, 4000, 10n ** 15n); // here vtoken should be put
    // await liquidityChange(4000, 5000, 10n ** 15n);
    await liquidityChange(1000, 4000, 10n ** 16n); // here vtoken should be put
  });

  const SWAP = {
    VTOKEN_FOR_VQUOTE: true,
    VQUOTE_FOR_VTOKEN: false,
  };

  const AMOUNT_TYPE_ENUM = {
    ZERO_FEE_VQUOTE_AMOUNT: 0,
    VQUOTE_AMOUNT_MINUS_FEES: 1,
    VQUOTE_AMOUNT_PLUS_FEES: 2,
  };

  describe('exactIn 1 ETH', () => {
    const amountSpecified = parseEther('1');
    const swapDirection = SWAP.VTOKEN_FOR_VQUOTE;

    let vTokenIn: BigNumber;
    let vQuoteIn: BigNumber;

    it('amountSpecified', async () => {
      ({ vTokenIn, vQuoteIn } = await vPoolWrapper.callStatic.swap(swapDirection, amountSpecified, 0));

      // when asked to charge 1 ETH, trader should be debited by that exactly and get whatever ETH
      expect(vTokenIn).to.eq(parseEther('1'));
    });

    let fees: BigNumber;
    let liquidityFees: BigNumber;
    it('swapped amount', async () => {
      const zeroFeeSim = await simulator.callStatic.simulateSwap3(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0);
      ({ fees, liquidityFees } = await calculateFees(zeroFeeSim.vQuoteIn, AMOUNT_TYPE_ENUM.ZERO_FEE_VQUOTE_AMOUNT));

      // comparing swap with a zero fee swap, vToken amounts should be same and
      // and vQuote amounts should be off by protocol + liquidity fees
      expect(vTokenIn).to.eq(zeroFeeSim.vTokenIn);
      expect(vQuoteIn).to.eq(zeroFeeSim.vQuoteIn.add(fees));

      // fees should be % of the zero fee swap amount
      expect(fees).to.eq(
        zeroFeeSim.vQuoteIn
          .abs()
          .mul(liquidityFee + protocolFee)
          .div(1e6)
          .add(1), // round up fees
      );
    });

    it('mint and burn', async () => {
      const { vTokenMintEvent, vQuoteBurnEvent } = await extractEvents(
        vPoolWrapper.swap(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0),
      );
      if (!vTokenMintEvent) {
        throw new Error('vTokenMintEvent not emitted');
      }
      if (!vQuoteBurnEvent) {
        throw new Error('vQuoteBurnEvent not emitted');
      }
      // amount is inflated, so the inflated amount is collected as fees by uniswap
      // and more vToken is minted to sell for fees
      expect(vTokenMintEvent.args.value).to.eq(inflate(amountSpecified));
      assert(vQuoteIn.isNegative());
      expect(vQuoteBurnEvent.args.value).to.eq(vQuoteIn.mul(-1).add(fees));
    });

    it('fee', async () => {
      const feeGlobal_before = await vPoolWrapper.sumFeeGlobalX128();
      await vPoolWrapper.swap(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0);
      const feeGlobal_after = await vPoolWrapper.sumFeeGlobalX128();

      const feePerLiquidityX128 = feeGlobal_after.sub(feeGlobal_before);
      const liquidity = await vPool.liquidity();

      const feesGivenToLP = feePerLiquidityX128.mul(liquidity).div(1n << 128n);
      // fees earned by LP == fees paid by trader,
      // error due to division underflow, LPs get paid less, and contract accumulates the dust
      expect(feesGivenToLP).to.lte(liquidityFees);
      expect(feesGivenToLP).to.gte(liquidityFees.sub(2));
    });

    it('sumB');
  });

  describe('exactIn 2000 USDC', () => {
    const amountSpecified = parseUsdc('2000');

    let vTokenIn: BigNumber;
    let vQuoteIn: BigNumber;

    it('amountSpecified', async () => {
      ({ vTokenIn, vQuoteIn } = await vPoolWrapper.callStatic.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0));

      // when asked to charge 2000 USDC, trader should be debited by that exactly and get whatever ETH it is
      expect(vQuoteIn).to.eq(parseUsdc('2000'));
    });

    let fees: BigNumber;
    let liquidityFees: BigNumber;
    it('swapped amount', async () => {
      ({ fees, liquidityFees } = await calculateFees(amountSpecified, AMOUNT_TYPE_ENUM.VQUOTE_AMOUNT_PLUS_FEES));
      const amountSpecifiedWithoutFee = amountSpecified.mul(1e6).div(1e6 + liquidityFee + protocolFee);
      const zeroFeeSim = await simulator.callStatic.simulateSwap3(SWAP.VQUOTE_FOR_VTOKEN, amountSpecifiedWithoutFee, 0);

      // comparing swap with a zero fee swap, vToken amounts should be same and
      // and vQuote amounts should be off by protocol + liquidity fees
      expect(vTokenIn).to.eq(zeroFeeSim.vTokenIn);
      // TODO there is missmatch in vQuote amount.
      expect(vQuoteIn).to.eq(zeroFeeSim.vQuoteIn.add(fees));

      // fees should be % of the zero fee swap amount
      expect(fees).to.eq(
        zeroFeeSim.vQuoteIn
          .abs()
          .mul(liquidityFee + protocolFee)
          .div(1e6)
          .add(1), // round up fees
      );
    });

    it('mint and burn', async () => {
      const { vQuoteMintEvent, vTokenBurnEvent } = await extractEvents(
        vPoolWrapper.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0),
      );
      if (!vTokenBurnEvent) {
        throw new Error('vTokenBurnEvent not emitted');
      }
      if (!vQuoteMintEvent) {
        throw new Error('vQuoteMintEvent not emitted');
      }

      // swap amount excludes protocol fee, liquidity fee
      // but amount is inflated to include uniswap fees, which is ignored later
      // and fee is collected so less vQuote is minted
      assert(vTokenIn.isNegative());
      expect(vTokenBurnEvent.args.value).to.eq(vTokenIn.mul(-1), 'mint mismatch');
      expect(vQuoteMintEvent.args.value).to.eq(inflate(amountSpecified.sub(fees)), 'mint mismatch');
    });

    it('fee', async () => {
      const feeGlobal_before = await vPoolWrapper.sumFeeGlobalX128();
      await vPoolWrapper.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0);
      const feeGlobal_after = await vPoolWrapper.sumFeeGlobalX128();

      const feePerLiquidityX128 = feeGlobal_after.sub(feeGlobal_before);
      const liquidity = await vPool.liquidity();

      const feesGivenToLP = feePerLiquidityX128.mul(liquidity).div(1n << 128n);
      // fees earned by LP == fees paid by trader,
      // error due to division underflow, LPs get paid less, and contract accumulates the dust
      expect(feesGivenToLP).to.lte(liquidityFees);
      expect(feesGivenToLP).to.gte(liquidityFees.sub(2));
    });

    it('sumB');
  });

  describe('exactOut 1 ETH', () => {
    const amountSpecified = parseEther('-1');
    let vTokenIn: BigNumber;
    let vQuoteIn: BigNumber;

    it('amountSpecified', async () => {
      ({ vTokenIn, vQuoteIn } = await vPoolWrapper.callStatic.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0));

      // when asked for 1 ETH output, trader should get that exactly and be charged whatever USDC it is
      assert(vTokenIn.isNegative());
      expect(vTokenIn.mul(-1)).to.eq(parseEther('1'));
    });

    let fees: BigNumber;
    let liquidityFees: BigNumber;
    it('swapped amount', async () => {
      const zeroFeeSim = await simulator.callStatic.simulateSwap3(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0);
      ({ fees, liquidityFees } = await calculateFees(zeroFeeSim.vQuoteIn, AMOUNT_TYPE_ENUM.ZERO_FEE_VQUOTE_AMOUNT));

      // comparing swap with a zero fee swap, vToken amounts should be same and
      // and vQuote amounts should be off by protocol + liquidity fees
      expect(vTokenIn).to.eq(zeroFeeSim.vTokenIn);
      expect(vQuoteIn).to.eq(zeroFeeSim.vQuoteIn.add(fees)); // vQuoteIn > 0

      // fees should be % of the zero fee swap amount
      expect(fees).to.eq(
        zeroFeeSim.vQuoteIn
          .abs()
          .mul(liquidityFee + protocolFee)
          .div(1e6)
          .add(1), // round up fees
      );
    });

    it('mint and burn', async () => {
      const { vTokenBurnEvent, vQuoteMintEvent } = await extractEvents(
        vPoolWrapper.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0),
      );
      if (!vTokenBurnEvent) {
        throw new Error('vTokenBurnEvent not emitted');
      }
      if (!vQuoteMintEvent) {
        throw new Error('vQuoteMintEvent not emitted');
      }
      // vToken ERC0 tokens that are bought, are burned by the vPoolWrapper
      // and just the value is returned to ClearingHouse
      expect(vTokenBurnEvent.args.value).to.eq(parseEther('1'));
      expect(vQuoteMintEvent.args.value).to.eq(inflate(vQuoteIn.sub(fees)));
    });

    it('fee', async () => {
      const feeGlobal_before = await vPoolWrapper.sumFeeGlobalX128();
      await vPoolWrapper.swap(SWAP.VQUOTE_FOR_VTOKEN, amountSpecified, 0);
      const feeGlobal_after = await vPoolWrapper.sumFeeGlobalX128();

      const feePerLiquidityX128 = feeGlobal_after.sub(feeGlobal_before);
      const liquidity = await vPool.liquidity();

      const feesGivenToLP = feePerLiquidityX128.mul(liquidity).div(1n << 128n);
      // fees earned by LP == fees paid by trader,
      // error due to division underflow, LPs get paid less, and contract accumulates the dust
      expect(feesGivenToLP).to.lte(liquidityFees);
      expect(feesGivenToLP).to.gte(liquidityFees.sub(2));
    });

    it('sumB');
  });

  describe('exactOut 2000 USDC', () => {
    const amountSpecified = parseUsdc('-2000');
    let vTokenIn: BigNumber;
    let vQuoteIn: BigNumber;

    it('amountSpecified', async () => {
      ({ vTokenIn, vQuoteIn } = await vPoolWrapper.callStatic.swap(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0));
      assert(vQuoteIn.isNegative());
      expect(vQuoteIn.mul(-1)).to.eq(parseUsdc('2000'));
    });

    let fees: BigNumber;
    let liquidityFees: BigNumber;
    it('swapped amount', async () => {
      ({ fees, liquidityFees } = await calculateFees(amountSpecified, AMOUNT_TYPE_ENUM.VQUOTE_AMOUNT_MINUS_FEES));

      const zeroFeeSim = await simulator.callStatic.simulateSwap3(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified.sub(fees), 0); // amountSpecified < 0

      // comparing swap with a zero fee swap, vToken amounts should be same and
      // and vQuote amounts should be off by protocol + liquidity fees
      expect(vTokenIn).to.eq(zeroFeeSim.vTokenIn);
      expect(vQuoteIn).to.eq(zeroFeeSim.vQuoteIn.add(fees)); // vQuoteIn < 0

      // fees should be % of the zero fee swap amount
      expect(fees).to.eq(
        zeroFeeSim.vQuoteIn
          .abs()
          .mul(liquidityFee + protocolFee)
          .div(1e6)
          .add(1), // round up fees
      );
    });

    it('mint and burn', async () => {
      const { vQuoteBurnEvent, vTokenMintEvent } = await extractEvents(
        vPoolWrapper.swap(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0),
      );
      if (!vTokenMintEvent) {
        throw new Error('vTokenMintEvent not emitted');
      }
      if (!vQuoteBurnEvent) {
        throw new Error('vQuoteMintEvent not emitted');
      }
      expect(vTokenMintEvent.args.value).to.eq(inflate(vTokenIn));
      expect(vQuoteBurnEvent.args.value).to.eq(parseUsdc('2000').add(fees));
    });

    it('fee', async () => {
      const feeGlobal_before = await vPoolWrapper.sumFeeGlobalX128();
      await vPoolWrapper.swap(SWAP.VTOKEN_FOR_VQUOTE, amountSpecified, 0);
      const feeGlobal_after = await vPoolWrapper.sumFeeGlobalX128();

      const feePerLiquidityX128 = feeGlobal_after.sub(feeGlobal_before);
      const liquidity = await vPool.liquidity();

      const feesGivenToLP = feePerLiquidityX128.mul(liquidity).div(1n << 128n);
      // fees earned by LP == fees paid by trader,
      // error due to division underflow, LPs get paid less, and contract accumulates the dust
      expect(feesGivenToLP).to.lte(liquidityFees);
      expect(feesGivenToLP).to.gte(liquidityFees.sub(2));
    });

    it('sumB');
  });

  function inflate(amount: BigNumberish): BigNumber {
    amount = BigNumber.from(amount);
    return amount.add(amount.mul(uniswapFee).div(1e6 - uniswapFee)).add(1); // round up
  }

  async function calculateFees(amount: BigNumberish, AMOUNT_TYPE_ENUM?: number) {
    const { liquidityFees, protocolFees } = await vPoolWrapper.calculateFees(amount, AMOUNT_TYPE_ENUM ?? 0);
    return { fees: liquidityFees.add(protocolFees), liquidityFees, protocolFees };
  }

  async function liquidityChange(priceLower: number, priceUpper: number, liquidityDelta: BigNumberish) {
    const tickSpacing = await vPool.tickSpacing();
    let tickLower = await priceToTick(priceLower, vQuote, vToken);
    let tickUpper = await priceToTick(priceUpper, vQuote, vToken);
    tickLower -= tickLower % tickSpacing;
    tickUpper -= tickUpper % tickSpacing;

    const priceLowerActual = await tickToPrice(tickLower, vQuote, vToken);
    const priceUpperActual = await tickToPrice(tickUpper, vQuote, vToken);
    // console.log(
    //   `adding liquidity between ${priceLowerActual} (tick: ${tickLower}) and ${priceUpperActual} (tick: ${tickUpper})`,
    // );

    if (!BigNumber.from(liquidityDelta).isNegative()) {
      await vPoolWrapper.mint(tickLower, tickUpper, liquidityDelta);
    } else {
      await vPoolWrapper.burn(tickLower, tickUpper, liquidityDelta);
    }
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
      vQuoteMintEvent: transferEvents.find(
        event => event.address === vQuote.address && event.args.from === ethers.constants.AddressZero,
      ),
      vQuoteBurnEvent: transferEvents.find(
        event => event.address === vQuote.address && event.args.to === ethers.constants.AddressZero,
      ),
    };
  }

  function parseUsdc(str: string): BigNumber {
    return parseUnits(str.replaceAll(',', '').replaceAll('_', ''), 6);
  }
});
