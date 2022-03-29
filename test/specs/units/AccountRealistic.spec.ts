import { expect } from 'chai';
import hre from 'hardhat';
import {
  VTokenPositionSetTest2,
  VPoolWrapper,
  UniswapV3Pool,
  AccountTest,
  RealTokenMock,
  ERC20,
  VQuote,
  OracleMock,
  RageTradeFactory,
  ClearingHouse,
  VToken,
} from '../../../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetupVQuote, testSetupToken } from '../../utils/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from '../../utils/mainnet-fork';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseTokenAmount } from '../../utils/stealFunds';
import {
  priceToSqrtPriceX96,
  priceToPriceX128,
  priceToTick,
  tickToSqrtPriceX96,
  sqrtPriceX96ToPriceX128,
  priceToNearestPriceX128,
  priceX128ToSqrtPriceX96,
  sqrtPriceX96ToTick,
} from '../../utils/price-tick';
import { amountsForLiquidity, maxLiquidityForAmounts } from '../../utils/liquidity';
import { randomInt } from 'crypto';
import { truncate } from '../../utils/vToken';
import { IClearingHouseStructures } from '../../../typechain-types/artifacts/contracts/interfaces/clearinghouse/IClearingHouseEvents';

describe('Account Library Test Realistic', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  // let constants: ConstantsStruct;
  let clearingHouse: ClearingHouse;
  let rageTradeFactory: RageTradeFactory;

  let test: AccountTest;
  let settlementToken: FakeContract<ERC20>;
  let vQuote: VQuote;
  let vQuoteAddress: string;
  let vToken: VToken;
  let minRequiredMargin: BigNumberish;
  let rangeLiquidationFeeFraction: BigNumberish;
  let liquidationParams: IClearingHouseStructures.LiquidationParamsStruct;
  let fixFee: BigNumberish;

  let oracle: OracleMock;
  let settlementTokenOracle: OracleMock;

  let vTokenAddress: string;
  let oracle1: OracleMock;
  let vTokenAddress1: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function changeVPoolPriceToNearestTick(price: number) {
    const tick = await priceToTick(price, vQuote, vToken);
    const sqrtPriceX96 = await priceToSqrtPriceX96(price, vQuote, vToken);
    vPoolFake.observe.returns([[0, tick * 60], []]);
    vPoolFake.slot0.returns(() => {
      return [sqrtPriceX96, tick, 0, 0, 0, 0, false];
    });
  }

  async function changeVPoolWrapperFakePrice(price: number) {
    const priceX128 = await priceToNearestPriceX128(price, vQuote, vToken);
    const sqrtPriceX96 = await priceToSqrtPriceX96(price, vQuote, vToken);

    vPoolWrapperFake.swap.returns((input: any) => {
      if (input.amountSpecified.gt(0) === input.swapVTokenForVQuote) {
        return [
          {
            amountSpecified: input.amountSpecified,
            vTokenIn: input.amountSpecified,
            vQuoteIn: input.amountSpecified
              .mul(priceX128)
              .div(1n << 128n)
              .mul(-1),
            liquidityFees: 0,
            protocolFees: 0,
            sqrtPriceX96Start: 0,
            sqrtPriceX96End: 0,
          },
        ];
      } else {
        return [
          {
            amountSpecified: input.amountSpecified,
            vTokenIn: input.amountSpecified
              .mul(-1)
              .mul(1n << 128n)
              .div(priceX128),
            vQuoteIn: input.amountSpecified,
            liquidityFees: 0,
            protocolFees: 0,
            sqrtPriceX96Start: 0,
            sqrtPriceX96End: 0,
          },
        ];
      }
    });

    vPoolWrapperFake.mint.returns((input: any) => {
      //   const sqrtPriceCurrent = priceX128ToSqrtPriceX96(priceX128);
      const sqrtPriceCurrent = sqrtPriceX96;
      const { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        input.tickLower,
        sqrtPriceCurrent,
        input.tickUpper,
        input.liquidity,
        true, // round up for add liquidity
      );

      return [
        vTokenAmount,
        vQuoteAmount,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ];
    });
    vPoolWrapperFake.burn.returns((input: any) => {
      //   const sqrtPriceCurrent = priceX128ToSqrtPriceX96(priceX128);
      const sqrtPriceCurrent = sqrtPriceX96;
      const { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        input.tickLower,
        sqrtPriceCurrent,
        input.tickUpper,
        input.liquidity,
        false, // round down for remove liquidity
      );

      return [
        vTokenAmount,
        vQuoteAmount,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ];
    });
  }

  function setWrapperValuesInside(sumBInside: BigNumberish) {
    vPoolWrapperFake.getValuesInside.returns([0, sumBInside, 0, 0]);
  }

  async function checkVTokenBalance(vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vVTokenBalance);
  }

  async function checkVQuoteBalance(vQuoteBalance: BigNumberish) {
    const vQuoteBalance_ = await test.getAccountQuoteBalance(0);
    expect(vQuoteBalance_).to.eq(vQuoteBalance);
  }

  async function checkTraderPosition(vTokenAddress: string, traderPosition: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.netTraderPosition).to.eq(traderPosition);
  }

  async function checkDepositBalance(vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(0, vTokenAddress);
    expect(balance).to.eq(vVTokenBalance);
  }

  async function checkAccountMarketValueAndRequiredMargin(
    isInitialMargin: boolean,
    expectedAccountMarketValue?: BigNumberish,
    expectedRequiredMargin?: BigNumberish,
  ) {
    const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, isInitialMargin);
    if (typeof expectedAccountMarketValue !== 'undefined') expect(accountMarketValue).to.eq(expectedAccountMarketValue);
    if (typeof expectedRequiredMargin !== 'undefined') expect(requiredMargin).to.eq(expectedRequiredMargin);
  }

  async function calculateNotionalAmountClosed(_vTokenAddress: string, _price: number) {
    const liquidityPositionNum = await test.getAccountLiquidityPositionNum(0, _vTokenAddress);
    const sqrtPriceCurrent = await priceToSqrtPriceX96(_price, vQuote, vToken);
    const priceCurrentX128 = await priceToNearestPriceX128(_price, vQuote, vToken);

    let vQuoteAmountTotal = BigNumber.from(0);
    let vTokenAmountTotal = BigNumber.from(0);

    for (let i = 0; i < liquidityPositionNum; i++) {
      const position = await test.getAccountLiquidityPositionDetails(0, _vTokenAddress, i);
      let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        position.tickLower,
        sqrtPriceCurrent,
        position.tickUpper,
        position.liquidity.mul(-1),
      );
      vQuoteAmountTotal = vQuoteAmountTotal.add(vQuoteAmount.mul(-1));
      vTokenAmountTotal = vTokenAmountTotal.add(vTokenAmount.mul(-1));
    }

    let notionalAmountClosed = vTokenAmountTotal
      .mul(priceCurrentX128)
      .div(1n << 128n)
      .add(vQuoteAmountTotal);
    return { vQuoteAmountTotal, vTokenAmountTotal, notionalAmountClosed };
  }

  async function checkLiquidityPositionNum(vTokenAddress: string, num: BigNumberish) {
    const outNum = await test.getAccountLiquidityPositionNum(0, vTokenAddress);
    expect(outNum).to.eq(num);
  }

  async function checkLiquidityPositionDetails(
    vTokenAddress: string,
    num: BigNumberish,
    tickLower?: BigNumberish,
    tickUpper?: BigNumberish,
    limitOrderType?: BigNumberish,
    liquidity?: BigNumberish,
    sumALastX128?: BigNumberish,
    sumBInsideLastX128?: BigNumberish,
    sumFpInsideLastX128?: BigNumberish,
    sumFeeInsideLastX128?: BigNumberish,
  ) {
    const out = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, num);
    if (typeof tickLower !== 'undefined') expect(out.tickLower).to.eq(tickLower);
    if (typeof tickUpper !== 'undefined') expect(out.tickUpper).to.eq(tickUpper);
    if (typeof limitOrderType !== 'undefined') expect(out.limitOrderType).to.eq(limitOrderType);
    if (typeof liquidity !== 'undefined') expect(out.liquidity).to.eq(liquidity);
    if (typeof sumALastX128 !== 'undefined') expect(out.sumALastX128).to.eq(sumALastX128);
    if (typeof sumBInsideLastX128 !== 'undefined') expect(out.sumBInsideLastX128).to.eq(sumBInsideLastX128);
    if (typeof sumFpInsideLastX128 !== 'undefined') expect(out.sumFpInsideLastX128).to.eq(sumFpInsideLastX128);
    if (typeof sumFeeInsideLastX128 !== 'undefined') expect(out.sumFeeInsideLastX128).to.eq(sumFeeInsideLastX128);
  }

  async function liquidityChange(
    tickLower: BigNumberish,
    tickUpper: BigNumberish,
    liquidityDelta: BigNumberish,
    closeTokenPosition: boolean,
    limitOrderType: number,
  ) {
    let liquidityChangeParams = {
      tickLower: tickLower,
      tickUpper: tickUpper,
      liquidityDelta: liquidityDelta,
      sqrtPriceCurrent: 0,
      slippageToleranceBps: 0,
      closeTokenPosition: closeTokenPosition,
      limitOrderType: limitOrderType,
    };

    await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
  }

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;
    let vPoolAddress1;
    let vPoolWrapperAddress1;
    ({
      settlementToken,
      vQuote,
      clearingHouse: clearingHouse,
      rageTradeFactory,
      oracle: settlementTokenOracle,
    } = await testSetupVQuote());

    ({
      oracle: oracle,
      vTokenAddress: vTokenAddress,
      vPoolAddress: vPoolAddress,
      vPoolWrapperAddress: vPoolWrapperAddress,
    } = await testSetupToken({
      decimals: 18,
      initialMarginRatioBps: 2000,
      maintainanceMarginRatioBps: 1000,
      twapDuration: 60,
      whitelisted: true,
      rageTradeFactory,
    }));

    ({
      oracle: oracle1,
      vTokenAddress: vTokenAddress1,
      vPoolAddress: vPoolAddress1,
      vPoolWrapperAddress: vPoolWrapperAddress1,
    } = await testSetupToken({
      decimals: 18,
      initialMarginRatioBps: 2000,
      maintainanceMarginRatioBps: 1000,
      twapDuration: 60,
      whitelisted: true,
      rageTradeFactory,
    }));
    vToken = await hre.ethers.getContractAt('VToken', vTokenAddress);
    vQuoteAddress = vQuote.address;

    vPoolFake = await smock.fake<UniswapV3Pool>(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      {
        address: vPoolAddress,
      },
    );
    vPoolFake.observe.returns([[0, 194430 * 60], []]);

    vPoolWrapperFake = await smock.fake<VPoolWrapper>('VPoolWrapper', {
      address: vPoolWrapperAddress,
    });
    // vPoolWrapperFake.timeHorizon.returns(60);
    // vPoolWrapperFake.maintainanceMarginRatio.returns(10000);
    // vPoolWrapperFake.initialMarginRatio.returns(20000);
    vPoolWrapperFake.vPool.returns(vPoolFake.address);
    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const factory = await hre.ethers.getContractFactory('AccountTest', {
      libraries: {
        Account: accountLib.address,
      },
    });
    test = await factory.deploy();
    await changeVPoolWrapperFakePrice(4000);

    liquidationParams = {
      rangeLiquidationFeeFraction: 1500,
      tokenLiquidationFeeFraction: 3000,
      insuranceFundFeeShareBps: 5000,
      maxRangeLiquidationFees: 100000000,
      closeFactorMMThresholdBps: 7500,
      partialLiquidationCloseFactorBps: 5000,
      liquidationSlippageSqrtToleranceBps: 150,
      minNotionalLiquidatable: 100000000,
    };
    fixFee = parseTokenAmount(0, 6);
    const removeLimitOrderFee = parseTokenAmount(10, 6);
    const minimumOrderNotional = parseTokenAmount(1, 6).div(100);
    const minRequiredMargin = parseTokenAmount(20, 6);

    await test.setAccountStorage(
      liquidationParams,
      removeLimitOrderFee,
      minimumOrderNotional,
      minRequiredMargin,
      fixFee,
      settlementToken.address,
    );

    const vTokenPoolObj = await clearingHouse.getPoolInfo(truncate(vTokenAddress));
    await test.registerPool(vTokenPoolObj);

    const vTokenPoolObj1 = await clearingHouse.getPoolInfo(truncate(vTokenAddress1));
    await test.registerPool(vTokenPoolObj1);

    await test.setVQuoteAddress(vQuote.address);
  });
  after(deactivateMainnetFork);
  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
      test.initToken(vTokenAddress1);
      test.initCollateral(settlementToken.address, settlementTokenOracle.address, 300);
    });
  });

  describe('Account Market Value and Required Margin', async () => {
    before(async () => {
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100, 6));
      await checkDepositBalance(settlementToken.address, parseTokenAmount(100, 6));
    });
    it('No Position', async () => {
      await checkAccountMarketValueAndRequiredMargin(true, parseTokenAmount(100, 6), 0);
    });
    it('Single Position', async () => {
      await changeVPoolPriceToNearestTick(4000);
      const { sqrtPriceX96, tick } = await vPoolFake.slot0();
      await test.swapTokenAmount(0, vTokenAddress, parseTokenAmount(1, 18).div(100));
      await checkAccountMarketValueAndRequiredMargin(true, parseTokenAmount(100, 6));
    });
    after(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
  });

  describe('#Margin', () => {
    after(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
    it('Add Margin', async () => {
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100, 6));
      await checkDepositBalance(settlementToken.address, parseTokenAmount(100, 6));
      await checkAccountMarketValueAndRequiredMargin(true, parseTokenAmount(100, 6), 0);
    });
    it('Remove Margin - Fail', async () => {
      await changeVPoolPriceToNearestTick(4000);

      await test.swapTokenAmount(0, vTokenAddress, parseTokenAmount(1, 18).div(10));

      let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, true);
      accountMarketValue = accountMarketValue.sub(parseTokenAmount(50, 6));

      await expect(test.removeMargin(0, settlementToken.address, parseTokenAmount(50, 6))).to.be.revertedWith(
        'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Remove Margin - Pass', async () => {
      test.cleanPositions(0);
      await test.removeMargin(0, settlementToken.address, parseTokenAmount(50, 6));
      await checkDepositBalance(settlementToken.address, parseTokenAmount(50, 6));
      await checkAccountMarketValueAndRequiredMargin(true, parseTokenAmount(50, 6), 0);
    });
  });

  describe('#Profit', () => {
    describe('#Token Position Profit', () => {
      before(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.addMargin(0, settlementToken.address, parseTokenAmount(100, 6));
        await test.swapTokenAmount(0, vTokenAddress, parseTokenAmount(1, 18).div(10));
      });
      after(async () => {
        await test.cleanPositions(0);
        await test.cleanDeposits(0);
      });
      it('Remove Profit - Fail (No Profit | Enough Margin)', async () => {
        let profit = (await test.getAccountProfit(0)).sub(parseTokenAmount(1, 6));
        await expect(test.updateProfit(0, parseTokenAmount(1, 6).mul(-1))).to.be.revertedWith(
          'InvalidTransactionNotEnoughProfit(' + profit + ')',
        );
      });
      it('Remove Profit - Fail (Profit Available | Not Enough Margin)', async () => {
        await changeVPoolPriceToNearestTick(4020);
        await test.removeMargin(0, settlementToken.address, parseTokenAmount(21, 6));
        let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, true);
        accountMarketValue = accountMarketValue.sub(parseTokenAmount(1, 6));
        await expect(test.updateProfit(0, parseTokenAmount(1, 6).mul(-1))).to.be.revertedWith(
          'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
        );
      });
      it('Remove Profit - Pass', async () => {
        await changeVPoolPriceToNearestTick(4050);
        const vQuoteDetails = await test.functions.getAccountQuoteBalance(0);
        await test.updateProfit(0, parseTokenAmount(1, 6).mul(-1));
        checkVQuoteBalance(vQuoteDetails.balance.sub(parseTokenAmount(1, 6)));
      });
      it('Deposit Loss - Pass', async () => {
        await changeVPoolPriceToNearestTick(4050);
        const vQuoteDetails = await test.functions.getAccountQuoteBalance(0);
        await test.updateProfit(0, parseTokenAmount(1, 6));
        checkVQuoteBalance(vQuoteDetails.balance.add(parseTokenAmount(1, 6)));
      });
    });
  });

  describe('#Trade - Swap Token Amount', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100, 6));
    });
    after(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
    it('Successful Trade', async () => {
      const tokenBalance = parseTokenAmount(1, 18).div(10 ** 2);
      const price = await priceToNearestPriceX128(4000, vQuote, vToken);

      const vQuoteBalance = tokenBalance
        .mul(price)
        .mul(-1)
        .div(1n << 128n);

      await test.swapTokenAmount(0, vTokenAddress, tokenBalance);
      await checkVTokenBalance(vTokenAddress, tokenBalance);
      await checkVQuoteBalance(vQuoteBalance);
    });
  });

  describe('#Trade - Swap Token Notional', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100, 6));
    });
    after(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
    it('Successful Trade', async () => {
      const vQuoteBalance = parseTokenAmount(50, 6);
      const price = await priceToNearestPriceX128(4000, vQuote, vToken);
      const tokenBalance = vQuoteBalance.mul(1n << 128n).div(price);

      await test.swapTokenNotional(0, vTokenAddress, vQuoteBalance);
      await checkVTokenBalance(vTokenAddress, tokenBalance);
      await checkVQuoteBalance(vQuoteBalance.mul(-1));
    });
  });

  describe('Limit Order Removal', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumber;
    before(async () => {
      tickLower = await priceToTick(3500, vQuote, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(4500, vQuote, vToken);
      tickUpper -= tickUpper % 10;
      liquidity = parseTokenAmount(1, 18);
    });
    beforeEach(async () => {
      await test.addMargin(0, settlementToken.address, parseTokenAmount(10000000, 6));
    });
    afterEach(async () => {
      await test.cleanDeposits(0);
      await test.cleanPositions(0);
    });
    it('Limit Order Removal (Upper) with Fee - No Price Change', async () => {
      await changeVPoolWrapperFakePrice(4600);
      await changeVPoolPriceToNearestTick(4600);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 2);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 2, liquidity);

      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, parseTokenAmount(5, 6));

      await checkVTokenBalance(vTokenAddress, 0);
      await checkVQuoteBalance(parseTokenAmount(-5, 6).sub(1));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Limit Order Removal (Lower) with Fee - No Price Change', async () => {
      await changeVPoolWrapperFakePrice(3400);
      await changeVPoolPriceToNearestTick(3400);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, parseTokenAmount(5, 6));

      await checkVTokenBalance(vTokenAddress, -1);
      await checkVQuoteBalance(parseTokenAmount(-5, 6));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });
    it('Limit Order Removal (Lower) with Fee - Price Change', async () => {
      await changeVPoolWrapperFakePrice(4000);
      await changeVPoolPriceToNearestTick(4000);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await changeVPoolWrapperFakePrice(3400);
      await changeVPoolPriceToNearestTick(3400);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(3400, vQuote, vToken));
      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, parseTokenAmount(5, 6));
      const { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity.mul(-1),
      );

      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.sub(vTokenAmount));
      await checkVQuoteBalance(startVQuoteDetails.balance.sub(vQuoteAmount).add(parseTokenAmount(-5, 6)));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Limit Order Removal Fail - Inactive Range', async () => {
      await changeVPoolWrapperFakePrice(4000);
      await changeVPoolPriceToNearestTick(4000);

      await test.addMargin(0, settlementToken.address, parseTokenAmount(10000000, 6));
      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await changeVPoolWrapperFakePrice(4600);
      await changeVPoolPriceToNearestTick(4600);

      await expect(
        test.removeLimitOrder(0, vTokenAddress, tickLower - 10, tickUpper, parseTokenAmount(5, 6)),
      ).to.be.revertedWith('InactiveRange()');
    });
  });

  describe('#Single Range Position Liquidation', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumber;
    let price: number;
    before(async () => {
      tickLower = await priceToTick(3500, vQuote, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(4500, vQuote, vToken);
      tickUpper -= tickUpper % 10;
      liquidity = parseTokenAmount(1, 18);
    });
    beforeEach(async () => {
      await changeVPoolWrapperFakePrice(3000);
      await changeVPoolPriceToNearestTick(3000);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(1200000, 6));
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
    });
    it('Liquidation - Fail (Account Above Water)', async () => {
      const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, false);
      await expect(test.liquidateLiquidityPositions(0)).to.be.revertedWith(
        'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Liquidation - Success (Account Positive)', async () => {
      price = 4100;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(0);
      const sqrtPriceCurrent = await priceToSqrtPriceX96(price, vQuote, vToken);
      let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity.mul(-1),
      );
      vQuoteAmount = vQuoteAmount.mul(-1);
      vTokenAmount = vTokenAmount.mul(-1);

      await test.liquidateLiquidityPositions(0);

      const priceCurrentX128 = await priceToNearestPriceX128(price, vQuote, vToken);
      const notionalAmountClosed = vQuoteAmount.add(vTokenAmount.mul(priceCurrentX128).div(1n << 128n));
      let fee = notionalAmountClosed.mul(liquidationParams.rangeLiquidationFeeFraction).div(1e5);
      fee = fee.gt(liquidationParams.maxRangeLiquidationFees)
        ? BigNumber.from(liquidationParams.maxRangeLiquidationFees)
        : fee;
      const feeHalf = fee.div(2);
      expect(keeperFee).to.eq(feeHalf.add(fixFee));
      expect(insuranceFundFee).to.eq(feeHalf);
      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkVQuoteBalance(startVQuoteDetails.balance.add(vQuoteAmount).sub(feeHalf.mul(2)).sub(fixFee));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Negative)', async () => {
      price = 4700;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, false);
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(0);

      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(price, vQuote, vToken));
      let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity.mul(-1),
      );
      vQuoteAmount = vQuoteAmount.mul(-1);
      vTokenAmount = vTokenAmount.mul(-1);
      await test.liquidateLiquidityPositions(0);

      const priceCurrentX128 = await priceToNearestPriceX128(price, vQuote, vToken);

      const notionalAmountClosed = vQuoteAmount.add(vTokenAmount.mul(priceCurrentX128).div(1n << 128n));
      let fee = notionalAmountClosed.mul(liquidationParams.rangeLiquidationFeeFraction).div(1e5);
      fee = fee.gt(liquidationParams.maxRangeLiquidationFees)
        ? BigNumber.from(liquidationParams.maxRangeLiquidationFees)
        : fee;
      const feeHalf = fee.div(2);
      const expectedKeeperFee = feeHalf.add(fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(feeHalf.add(fixFee));

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).gt(keeperFee);
      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkVQuoteBalance(
        startVQuoteDetails.balance.add(vQuoteAmount).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    afterEach(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
  });

  describe('#Multiple Range Position Liquidation', () => {
    let tickLower: number;
    let tickUpper: number;
    let tickLower1: number;
    let tickUpper1: number;
    let liquidity: BigNumber;
    let price: number;
    before(async () => {
      tickLower = await priceToTick(3500, vQuote, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(4500, vQuote, vToken);
      tickUpper -= tickUpper % 10;
      tickLower1 = tickLower - 100;
      tickUpper1 = tickUpper + 100;
      liquidity = parseTokenAmount(1, 18).div(2);
    });
    beforeEach(async () => {
      await changeVPoolWrapperFakePrice(3000);
      await changeVPoolPriceToNearestTick(3000);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(1250000, 6));
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
      await liquidityChange(tickLower1, tickUpper1, liquidity, false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 2);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
      await checkLiquidityPositionDetails(vTokenAddress, 1, tickLower1, tickUpper1, 0, liquidity);
    });
    it('Liquidation - Fail (Account Above Water)', async () => {
      const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, false);
      await expect(test.liquidateLiquidityPositions(0)).to.be.revertedWith(
        'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Liquidation - Success (Account Positive)', async () => {
      price = 4100;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(0);

      const { vQuoteAmountTotal, vTokenAmountTotal, notionalAmountClosed } = await calculateNotionalAmountClosed(
        vTokenAddress,
        price,
      );

      await test.liquidateLiquidityPositions(0);
      let liquidationFee = notionalAmountClosed.mul(liquidationParams.rangeLiquidationFeeFraction).div(1e5);
      liquidationFee = liquidationFee.gt(liquidationParams.maxRangeLiquidationFees)
        ? BigNumber.from(liquidationParams.maxRangeLiquidationFees)
        : liquidationFee;
      const expectedKeeperFee = liquidationFee
        .mul(10n ** 4n - BigNumber.from(liquidationParams.insuranceFundFeeShareBps).toBigInt())
        .div(1e4)
        .add(fixFee);
      const expectedInsuranceFundFee = liquidationFee.sub(keeperFee).add(fixFee);

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmountTotal));
      await checkVQuoteBalance(startVQuoteDetails.balance.add(vQuoteAmountTotal).sub(liquidationFee).sub(fixFee));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Negative)', async () => {
      price = 4700;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(0, false);
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(0);

      const { vQuoteAmountTotal, vTokenAmountTotal, notionalAmountClosed } = await calculateNotionalAmountClosed(
        vTokenAddress,
        price,
      );

      await test.liquidateLiquidityPositions(0);

      let liquidationFee = notionalAmountClosed.mul(liquidationParams.rangeLiquidationFeeFraction).div(1e5);
      liquidationFee = liquidationFee.gt(liquidationParams.maxRangeLiquidationFees)
        ? BigNumber.from(liquidationParams.maxRangeLiquidationFees)
        : liquidationFee;
      const expectedKeeperFee = liquidationFee
        .mul(10n ** 4n - BigNumber.from(liquidationParams.insuranceFundFeeShareBps).toBigInt())
        .div(1e4)
        .add(fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(keeperFee);

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).gt(keeperFee);
      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmountTotal));
      await checkVQuoteBalance(
        startVQuoteDetails.balance.add(vQuoteAmountTotal).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    afterEach(async () => {
      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
  });

  describe('#Trade- Liquidity Change', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumber;
    let netSumB: BigNumber;
    before(async () => {
      tickLower = await priceToTick(3500, vQuote, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(4500, vQuote, vToken);
      tickUpper -= tickUpper % 10;
      netSumB = BigNumber.from(0);
    });

    beforeEach(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await changeVPoolWrapperFakePrice(4000);
      liquidity = parseTokenAmount(100000, 6);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100000, 6));
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
    });

    afterEach(async () => {
      //Makes sumBInsideLast = 0
      setWrapperValuesInside(0);
      await liquidityChange(tickLower, tickUpper, 1, false, 0);

      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });
    it('Successful Add', async () => {
      const price = 4000;
      const sqrtPriceCurrent = await priceToSqrtPriceX96(price, vQuote, vToken);

      const { vQuoteAmount, vTokenAmount } = amountsForLiquidity(tickLower, sqrtPriceCurrent, tickUpper, liquidity);
      await checkVTokenBalance(vTokenAddress, vTokenAmount.mul(-1));
      await checkVQuoteBalance(vQuoteAmount.mul(-1));
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
    });

    it('Successful Remove (No Net Position)', async () => {
      liquidity = liquidity.mul(-1);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);

      await checkVTokenBalance(vTokenAddress, -1);
      await checkVQuoteBalance(-1);
      await checkLiquidityPositionNum(vTokenAddress, 0);
      await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6).sub(1));
    });

    it('Successful Remove And Close (No Net Position)', async () => {
      liquidity = liquidity.mul(-1);
      await liquidityChange(tickLower, tickUpper, liquidity, true, 0);
      await checkVTokenBalance(vTokenAddress, 0);
      await checkVQuoteBalance(-1);
      await checkLiquidityPositionNum(vTokenAddress, 0);
      await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6).sub(1));
    });

    it('Successful Add (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vQuote, vToken);
      const sqrtPriceCurrent = await priceToSqrtPriceX96(price, vQuote, vToken);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(tickLower, sqrtPriceCurrent, tickUpper, liquidity);
      vQuoteAmount = vQuoteAmount.mul(-1);
      vTokenAmount = vTokenAmount.mul(-1);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);

      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkVQuoteBalance(startVQuoteDetails.balance.add(vQuoteAmount));
      await checkTraderPosition(vTokenAddress, startTokenDetails.balance.sub(vTokenAmount).sub(1));
      await checkLiquidityPositionNum(vTokenAddress, 1);
      // await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6));
    });

    it('Successful Remove (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vQuote, vToken);
      const sqrtPriceCurrent = await priceToSqrtPriceX96(price, vQuote, vToken);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      liquidity = liquidity.mul(-1);
      const { vQuoteAmount, vTokenAmount } = amountsForLiquidity(tickLower, sqrtPriceCurrent, tickUpper, liquidity);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);

      await checkVTokenBalance(vTokenAddress, startTokenDetails.balance.sub(vTokenAmount));
      await checkVQuoteBalance(startVQuoteDetails.balance.sub(vQuoteAmount));
      await checkTraderPosition(vTokenAddress, startTokenDetails.balance.sub(vTokenAmount));
      await checkLiquidityPositionNum(vTokenAddress, 0);
      // await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6));
    });

    it('Successful Add And Close (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vQuote, vToken);
      const sqrtPriceCurrent = await priceToSqrtPriceX96(price, vQuote, vToken);
      const priceX128 = await priceToNearestPriceX128(price, vQuote, vToken);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      let vQuoteAmountIn;
      let vTokenAmountIn;
      let vQuoteAmountOut;
      let vTokenAmountOut;
      {
        let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(tickLower, sqrtPriceCurrent, tickUpper, liquidity);

        vQuoteAmountIn = vQuoteAmount.mul(-1);
        vTokenAmountIn = vTokenAmount.mul(-1);
      }
      {
        let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(
          tickLower,
          sqrtPriceCurrent,
          tickUpper,
          liquidity.mul(-1),
        );

        vQuoteAmountOut = vQuoteAmount;
        vTokenAmountOut = vTokenAmount;
      }

      await liquidityChange(tickLower, tickUpper, liquidity, true, 0);

      await checkVTokenBalance(
        vTokenAddress,
        startTokenDetails.balance.add(vTokenAmountIn).sub(startTokenDetails.balance.sub(vTokenAmountOut)),
      );
      const vQuoteAmountSwapped = startTokenDetails.balance
        .sub(vTokenAmountOut)
        .mul(priceX128)
        .div(1n << 128n);
      await checkVQuoteBalance(startVQuoteDetails.balance.add(vQuoteAmountIn).add(vQuoteAmountSwapped));
      await checkTraderPosition(vTokenAddress, 0);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      // await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6));
    });

    it('Successful Remove And Close (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vQuote, vToken);
      const sqrtPriceCurrent = tickToSqrtPriceX96(tick);
      const priceX128Current = await priceToNearestPriceX128(price, vQuote, vToken);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startVQuoteDetails = await test.functions.getAccountQuoteBalance(0);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      liquidity = liquidity.mul(-1);
      let { vQuoteAmount, vTokenAmount } = amountsForLiquidity(tickLower, sqrtPriceCurrent, tickUpper, liquidity);

      await liquidityChange(tickLower, tickUpper, liquidity, true, 0);

      const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
      //TODO: !!!!! Check how to fix this !!!!!
      // expect(vTokenPosition.balance.abs()).lte(1);
      // expect(vTokenPosition.netTraderPosition.abs()).lte(1);
      await checkVTokenBalance(vTokenAddress, 0);
      await checkTraderPosition(vTokenAddress, 0);
      const vQuoteAmountSwapped = startTokenDetails.balance
        .sub(vTokenAmount)
        .mul(priceX128Current)
        .div(1n << 128n);
      await checkVQuoteBalance(startVQuoteDetails.balance.sub(vQuoteAmount).add(vQuoteAmountSwapped));
      await checkLiquidityPositionNum(vTokenAddress, 0);
      // await checkAccountMarketValueAndRequiredMargin(false, parseTokenAmount(100000, 6));
    });
  });

  describe('#Trade- Multiple Liquidity Add & Remove', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumber;
    let netSumB: BigNumber;
    before(async () => {
      tickLower = await priceToTick(3500, vQuote, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(4500, vQuote, vToken);
      tickUpper -= tickUpper % 10;
      netSumB = BigNumber.from(0);
    });

    beforeEach(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await changeVPoolWrapperFakePrice(4000);
      await test.addMargin(0, settlementToken.address, parseTokenAmount(100000, 6));
    });

    afterEach(async () => {
      //Makes sumBInsideLast = 0
      setWrapperValuesInside(0);
      await liquidityChange(tickLower, tickUpper, 1, false, 0);

      await test.cleanPositions(0);
      await test.cleanDeposits(0);
    });

    for (let index = 0; index < 10; index++) {
      let liqNum = randomInt(20) + 1;
      let smallLiqAddNum = randomInt(50);
      let smallLiqRemoveNum = randomInt(50);
      it('Test #' + (index + 1) + ' (' + liqNum + ', ' + smallLiqAddNum + ', ' + smallLiqRemoveNum + ')', async () => {
        liquidity = parseTokenAmount(1, 6);

        for (let i = 0; i < liqNum; i++) {
          await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
        }

        for (let i = 0; i < smallLiqAddNum; i++) {
          await liquidityChange(tickLower, tickUpper, 1, false, 0);
        }

        for (let i = 0; i < smallLiqRemoveNum; i++) {
          await liquidityChange(tickLower, tickUpper, -1, false, 0);
        }

        for (let i = 0; i < liqNum - 1; i++) {
          await liquidityChange(tickLower, tickUpper, -liquidity, false, 0);
        }

        await liquidityChange(tickLower, tickUpper, -liquidity + smallLiqRemoveNum - smallLiqAddNum, false, 0);

        const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
        const liquidityPosition = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);
        expect(vTokenPosition.balance).eq(vTokenPosition.netTraderPosition);
        expect(liquidityPosition.liquidity).eq(0);
        expect(liquidityPosition.vTokenAmountIn).eq(0);
      });
    }
  });
});
