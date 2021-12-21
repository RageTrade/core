import { expect } from 'chai';
import hre from 'hardhat';
import {
  VTokenPositionSetTest2,
  VPoolWrapper,
  UniswapV3Pool,
  AccountTest,
  RealTokenMock,
  ERC20,
  VBase,
  OracleMock,
  VPoolFactory,
  ClearingHouse,
  VToken,
} from '../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetupBase, testSetupToken } from './utils/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { tokenAmount } from './utils/stealFunds';
import {
  priceToSqrtPriceX96,
  priceToPriceX128,
  priceToTick,
  tickToSqrtPriceX96,
  sqrtPriceX96ToPriceX128,
  priceToNearestPriceX128,
  priceX128ToSqrtPriceX96,
  sqrtPriceX96ToTick,
} from './utils/price-tick';
import { amountsForLiquidity, maxLiquidityForAmounts } from './utils/liquidity';

describe('Account Library Test Realistic', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  let constants: ConstantsStruct;
  let clearingHouse: ClearingHouse;
  let vPoolFactory: VPoolFactory;

  let test: AccountTest;
  let realBase: FakeContract<ERC20>;
  let vBase: FakeContract<VBase>;
  let vBaseAddress: string;
  let vToken: VToken;
  let minRequiredMargin: BigNumberish;
  let liquidationFeeFraction: BigNumberish;
  let liquidationParams: any;

  let oracle: OracleMock;
  let vTokenAddress: string;
  let oracle1: OracleMock;
  let vTokenAddress1: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function changeVPoolPriceToNearestTick(price: number) {
    const tick = await priceToTick(price, vBase, vToken);
    vPoolFake.observe.returns([[0, tick * 60], []]);
    vPoolFake.slot0.returns([0, tick, 0, 0, 0, 0, 0]);
  }

  async function changeVPoolWrapperFakePrice(price: number) {
    const priceX128 = await priceToNearestPriceX128(price, vBase, vToken);

    vPoolWrapperFake.swapToken.returns((input: any) => {
      if (input.isNotional) {
        return [
          input.amount
            .mul(1n << 128n)
            .div(priceX128)
            .mul(-1),
          input.amount,
        ];
      } else {
        return [input.amount.mul(-1), input.amount.mul(priceX128).div(1n << 128n)];
      }
    });

    vPoolWrapperFake.liquidityChange.returns((input: any) => {
      const sqrtPriceCurrent = priceX128ToSqrtPriceX96(priceX128, vBase, vToken);

      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        input.tickLower,
        sqrtPriceCurrent,
        input.tickUpper,
        input.liquidityDelta,
        vBase,
        vToken,
      );

      return [vBaseAmount, vTokenAmount];
    });
  }

  function setWrapperValuesInside(sumBInside: BigNumberish) {
    vPoolWrapperFake.getValuesInside.returns([0, sumBInside, 0, 0]);
  }

  async function checkTokenBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
  }

  async function checkTraderPosition(vTokenAddress: string, traderPosition: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.netTraderPosition).to.eq(traderPosition);
  }

  async function checkDepositBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(0, vTokenAddress);
    expect(balance).to.eq(vTokenBalance);
  }

  async function checkAccountMarketValueAndRequiredMargin(
    isInitialMargin: boolean,
    expectedAccountMarketValue?: BigNumberish,
    expectedRequiredMargin?: BigNumberish,
  ) {
    const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
      0,
      isInitialMargin,
      minRequiredMargin,
      constants,
    );
    if (typeof expectedAccountMarketValue !== 'undefined') expect(accountMarketValue).to.eq(expectedAccountMarketValue);
    if (typeof expectedRequiredMargin !== 'undefined') expect(requiredMargin).to.eq(expectedRequiredMargin);
  }

  async function calculateNotionalAmountClosed(_vTokenAddress: string, _price: number) {
    const liquidityPositionNum = await test.getAccountLiquidityPositionNum(0, _vTokenAddress);
    const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(_price, vBase, vToken));
    const priceCurrentX128 = await priceToNearestPriceX128(_price, vBase, vToken);

    let vBaseAmountTotal = BigNumber.from(0);
    let vTokenAmountTotal = BigNumber.from(0);

    for (let i = 0; i < liquidityPositionNum; i++) {
      const position = await test.getAccountLiquidityPositionDetails(0, _vTokenAddress, i);
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        position.tickLower,
        sqrtPriceCurrent,
        position.tickUpper,
        position.liquidity,
        vBase,
        vToken,
      );

      vBaseAmountTotal = vBaseAmountTotal.add(vBaseAmount);
      vTokenAmountTotal = vTokenAmountTotal.add(vTokenAmount);
    }

    let notionalAmountClosed = vTokenAmountTotal
      .mul(priceCurrentX128)
      .div(1n << 128n)
      .add(vBaseAmountTotal);
    return { vBaseAmountTotal, vTokenAmountTotal, notionalAmountClosed };
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

    await test.liquidityChange(0, vTokenAddress, liquidityChangeParams, 0, constants);
  }

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;
    let vPoolAddress1;
    let vPoolWrapperAddress1;
    ({
      realbase: realBase,
      vBase: vBase,
      clearingHouse: clearingHouse,
      vPoolFactory: vPoolFactory,
      constants: constants,
    } = await testSetupBase({
      isVTokenToken0: false,
    }));

    ({
      oracle: oracle,
      vTokenAddress: vTokenAddress,
      vPoolAddress: vPoolAddress,
      vPoolWrapperAddress: vPoolWrapperAddress,
    } = await testSetupToken({
      decimals: 18,
      initialMarginRatio: 20000,
      maintainanceMarginRatio: 10000,
      twapDuration: 60,
      whitelisted: true,
      vPoolFactory: vPoolFactory,
    }));

    ({
      oracle: oracle1,
      vTokenAddress: vTokenAddress1,
      vPoolAddress: vPoolAddress1,
      vPoolWrapperAddress: vPoolWrapperAddress1,
    } = await testSetupToken({
      decimals: 18,
      initialMarginRatio: 20000,
      maintainanceMarginRatio: 10000,
      twapDuration: 60,
      whitelisted: true,
      vPoolFactory: vPoolFactory,
    }));

    vToken = await hre.ethers.getContractAt('VToken', vTokenAddress);
    vBaseAddress = vBase.address;

    vPoolFake = await smock.fake<UniswapV3Pool>('IUniswapV3Pool', {
      address: vPoolAddress,
    });
    vPoolFake.observe.returns([[0, 194430 * 60], []]);

    vPoolWrapperFake = await smock.fake<VPoolWrapper>('VPoolWrapper', {
      address: vPoolWrapperAddress,
    });
    vPoolWrapperFake.timeHorizon.returns(60);
    vPoolWrapperFake.maintainanceMarginRatio.returns(10000);
    vPoolWrapperFake.initialMarginRatio.returns(20000);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const factory = await hre.ethers.getContractFactory('AccountTest', {
      libraries: {
        Account: accountLib.address,
      },
    });
    test = await factory.deploy();

    await changeVPoolWrapperFakePrice(4000);
    minRequiredMargin = tokenAmount(20, 6);
    liquidationParams = {
      fixFee: tokenAmount(10, 6),
      minRequiredMargin: minRequiredMargin,
      liquidationFeeFraction: 1500,
      tokenLiquidationPriceDeltaBps: 3000,
      insuranceFundFeeShareBps: 5000,
    };
  });
  after(deactivateMainnetFork);
  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
      test.initToken(vTokenAddress1);
    });
  });

  describe('Account Market Value and Required Margin', async () => {
    before(async () => {
      await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(100, 6));
    });
    it('No Position', async () => {
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(100, 6), 0);
    });
    it('Single Position', async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.swapTokenAmount(0, vTokenAddress, tokenAmount(1, 18).div(100), minRequiredMargin, constants);
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(100, 6), minRequiredMargin);
    });
    after(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
  });

  describe('#Margin', () => {
    after(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
    it('Add Margin', async () => {
      await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(100, 6));
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(100, 6), 0);
    });
    it('Remove Margin - Fail', async () => {
      await changeVPoolPriceToNearestTick(4000);

      await test.swapTokenAmount(0, vTokenAddress, tokenAmount(1, 18).div(10), minRequiredMargin, constants);

      let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        0,
        true,
        minRequiredMargin,
        constants,
      );
      accountMarketValue = accountMarketValue.sub(tokenAmount(50, 6));

      expect(test.removeMargin(0, vBaseAddress, tokenAmount(50, 6), minRequiredMargin, constants)).to.be.revertedWith(
        'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Remove Margin - Pass', async () => {
      test.cleanPositions(0, constants);
      await test.removeMargin(0, vBaseAddress, tokenAmount(50, 6), minRequiredMargin, constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(50, 6));
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(50, 6), 0);
    });
  });

  describe('#Profit', () => {
    describe('#Token Position Profit', () => {
      before(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
        await test.swapTokenAmount(0, vTokenAddress, tokenAmount(1, 18).div(10), minRequiredMargin, constants);
      });
      after(async () => {
        await test.cleanPositions(0, constants);
        await test.cleanDeposits(0, constants);
      });
      it('Remove Profit - Fail (No Profit | Enough Margin)', async () => {
        let profit = (await test.getAccountProfit(0, constants)).sub(tokenAmount(1, 6));
        expect(test.removeProfit(0, tokenAmount(1, 6), minRequiredMargin, constants)).to.be.revertedWith(
          'InvalidTransactionNotEnoughProfit(' + profit + ')',
        );
      });
      it('Remove Profit - Fail (Profit Available | Not Enough Margin)', async () => {
        await changeVPoolPriceToNearestTick(4020);
        await test.removeMargin(0, vBaseAddress, tokenAmount(21, 6), minRequiredMargin, constants);
        let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          true,
          minRequiredMargin,
          constants,
        );
        accountMarketValue = accountMarketValue.sub(tokenAmount(1, 6));
        expect(test.removeProfit(0, tokenAmount(1, 6), minRequiredMargin, constants)).to.be.revertedWith(
          'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
        );
      });
      it('Remove Profit - Pass', async () => {
        await changeVPoolPriceToNearestTick(4050);
        const baseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        await test.removeProfit(0, tokenAmount(1, 6), minRequiredMargin, constants);
        checkTokenBalance(vBaseAddress, baseDetails.balance.sub(tokenAmount(1, 6)));
      });
    });
  });

  describe('#Trade - Swap Token Amount', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
    });
    after(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
    it('Successful Trade', async () => {
      const tokenBalance = tokenAmount(1, 18).div(10 ** 2);
      const price = await priceToNearestPriceX128(4000, vBase, vToken);

      const baseBalance = tokenBalance
        .mul(price)
        .mul(-1)
        .div(1n << 128n);

      await test.swapTokenAmount(0, vTokenAddress, tokenBalance, minRequiredMargin, constants);
      await checkTokenBalance(vTokenAddress, tokenBalance);
      await checkTokenBalance(vBaseAddress, baseBalance);
    });
  });

  describe('#Trade - Swap Token Notional', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
    });
    after(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
    it('Successful Trade', async () => {
      const baseBalance = tokenAmount(50, 6);
      const price = await priceToNearestPriceX128(4000, vBase, vToken);
      const tokenBalance = baseBalance.mul(1n << 128n).div(price);

      await test.swapTokenNotional(0, vTokenAddress, baseBalance, minRequiredMargin, constants);
      await checkTokenBalance(vTokenAddress, tokenBalance);
      await checkTokenBalance(vBaseAddress, baseBalance.mul(-1));
    });
  });

  describe('#Token Liquidation', () => {
    describe('#Token Position Liquidation Helpers', () => {
      it('Liquidation at 4000 ', async () => {
        await changeVPoolPriceToNearestTick(4000);
        const priceX128 = await priceToNearestPriceX128(4000, vBase, vToken);
        const tokensToTrade = tokenAmount(-1, 18);
        const { liquidationPriceX128, liquidatorPriceX128, insuranceFundFee } =
          await test.getLiquidationPriceX128AndFee(tokensToTrade, vTokenAddress, liquidationParams, constants);
        expect(liquidationPriceX128).to.eq(priceX128.sub(priceX128.mul(300).div(10000)));
        expect(liquidatorPriceX128).to.eq(priceX128.sub(priceX128.mul(150).div(10000)));
        expect(insuranceFundFee).to.eq(
          tokensToTrade
            .mul(-1)
            .mul(liquidatorPriceX128.sub(liquidationPriceX128))
            .div(1n << 128n),
        );
      });
      it('Liquidation at 3500 ', async () => {
        await changeVPoolPriceToNearestTick(3500);
        const tokensToTrade = tokenAmount(1, 18);
        const priceX128 = await priceToNearestPriceX128(3500, vBase, vToken);
        const { liquidationPriceX128, liquidatorPriceX128, insuranceFundFee } =
          await test.getLiquidationPriceX128AndFee(tokensToTrade, vTokenAddress, liquidationParams, constants);

        expect(liquidationPriceX128).to.eq(priceX128.add(priceX128.mul(300).div(10000)));
        expect(liquidatorPriceX128).to.eq(priceX128.add(priceX128.mul(150).div(10000)));
        expect(insuranceFundFee).to.eq(
          tokensToTrade.mul(liquidationPriceX128.sub(liquidatorPriceX128)).div(1n << 128n),
        );
      });
    });

    describe('#Token Position Liquidation Scenarios', () => {
      beforeEach(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
        await test.addMargin(1, vBaseAddress, tokenAmount(1000, 6), constants);

        const baseBalance = tokenAmount(500, 6);

        await test.swapTokenNotional(0, vTokenAddress, baseBalance, minRequiredMargin, constants);
      });

      afterEach(async () => {
        await test.cleanDeposits(0, constants);
        await test.cleanPositions(0, constants);
        await test.cleanDeposits(1, constants);
        await test.cleanPositions(1, constants);
      });

      it('Liquidation - Fail (Account Above Water)', async () => {
        await changeVPoolPriceToNearestTick(4000);

        let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
          'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
        );
      });
      it('Liquidation - Fail (Active Range Present)', async () => {
        await test.addMargin(0, vTokenAddress, tokenAmount(1000000, 6), constants);

        await liquidityChange(194000, 195000, tokenAmount(1, 18), false, 0);

        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
          'InvalidLiquidationActiveRangePresent("' + vTokenAddress + '")',
        );
      });
      it('Liquidation - Fail (Liquidator Not Enough Margin)', async () => {
        await test.removeMargin(1, vBaseAddress, tokenAmount(1000, 6), minRequiredMargin, constants);

        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.reverted;
      });
      it('Liquidation Fail (No Token Position)', async () => {
        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress1, liquidationParams, constants)).to.be.revertedWith(
          'TokenInactive("' + vTokenAddress1 + '")',
        );
      });
      it('Liquidation - Success', async () => {
        await changeVPoolPriceToNearestTick(3500);

        const startLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const startLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);

        await test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants);

        const endLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const liquidatorTokenDetails = await test.getAccountTokenDetails(1, vTokenAddress);
        const endLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const liquidatorBaseDetails = await test.getAccountTokenDetails(1, vBaseAddress);

        const priceX128 = await priceToNearestPriceX128(3500, vBase, vToken);
        const liquidationPriceX128 = priceX128.sub(priceX128.mul(300).div(10000));
        const liquidatorPriceX128 = priceX128.sub(priceX128.mul(150).div(10000));

        expect(endLiquidatedTokenDetails.balance).to.eq(0);
        expect(liquidatorTokenDetails.balance).to.eq(startLiquidatedTokenDetails.balance);
        expect(endLiquidatedBaseDetails.balance).to.eq(
          startLiquidatedBaseDetails.balance
            .add(startLiquidatedTokenDetails.balance.mul(liquidationPriceX128).div(1n << 128n))
            .sub(liquidationParams.fixFee),
        );
        expect(liquidatorBaseDetails.balance).to.eq(
          startLiquidatedTokenDetails.balance
            .mul(liquidatorPriceX128)
            .div(1n << 128n)
            .mul(-1)
            .add(liquidationParams.fixFee),
        );
      });

      it('Liquidation (Account Negative Afterwards)- Success', async () => {
        await test.addMargin(1, vBaseAddress, tokenAmount(1000, 6), constants);
        await changeVPoolPriceToNearestTick(3000);

        const startLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const startLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const startLiquidatedBaseDeposits = await test.getAccountDepositBalance(0, vBaseAddress);

        await test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants);

        const endLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const liquidatorTokenDetails = await test.getAccountTokenDetails(1, vTokenAddress);
        const endLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const liquidatorBaseDetails = await test.getAccountTokenDetails(1, vBaseAddress);

        const priceX128 = await priceToNearestPriceX128(3000, vBase, vToken);
        const liquidationPriceX128 = priceX128.sub(priceX128.mul(300).div(10000));
        const liquidatorPriceX128 = priceX128.sub(priceX128.mul(150).div(10000));

        expect(endLiquidatedTokenDetails.balance).to.eq(0);
        expect(liquidatorTokenDetails.balance).to.eq(startLiquidatedTokenDetails.balance);
        expect(endLiquidatedBaseDetails.balance).to.eq(startLiquidatedBaseDeposits.mul(-1));
        expect(liquidatorBaseDetails.balance).to.eq(
          startLiquidatedTokenDetails.balance
            .mul(liquidatorPriceX128)
            .div(1n << 128n)
            .mul(-1)
            .add(liquidationParams.fixFee),
        );
      });
    });

    describe('#Token Position Liquidation Scenarios (Short Position)', () => {
      beforeEach(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
        await test.addMargin(1, vBaseAddress, tokenAmount(1000, 6), constants);

        const baseBalance = tokenAmount(500, 6).mul(-1);

        await test.swapTokenNotional(0, vTokenAddress, baseBalance, minRequiredMargin, constants);
      });
      afterEach(async () => {
        await test.cleanDeposits(0, constants);
        await test.cleanPositions(0, constants);
        await test.cleanDeposits(1, constants);
        await test.cleanPositions(1, constants);
      });
      it('Liquidation - Fail (Account Above Water)', async () => {
        await changeVPoolPriceToNearestTick(4000);

        let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
          'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
        );
      });
      it('Liquidation - Fail (Active Range Present)', async () => {
        await test.addMargin(0, vTokenAddress, tokenAmount(1000000, 6), constants);

        await liquidityChange(194000, 195000, tokenAmount(1, 18), false, 0);

        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
          'InvalidLiquidationActiveRangePresent("' + vTokenAddress + '")',
        );
      });
      it('Liquidation - Fail (Liquidator Not Enough Margin)', async () => {
        await test.removeMargin(1, vBaseAddress, tokenAmount(1000, 6), minRequiredMargin, constants);

        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.reverted;
      });
      it('Liquidation - Success', async () => {
        await changeVPoolPriceToNearestTick(4500);

        const startLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const startLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);

        await test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants);

        const endLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const liquidatorTokenDetails = await test.getAccountTokenDetails(1, vTokenAddress);
        const endLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const liquidatorBaseDetails = await test.getAccountTokenDetails(1, vBaseAddress);

        const priceX128 = await priceToNearestPriceX128(4500, vBase, vToken);
        const liquidationPriceX128 = priceX128.add(priceX128.mul(300).div(10000));
        const liquidatorPriceX128 = priceX128.add(priceX128.mul(150).div(10000));

        expect(endLiquidatedTokenDetails.balance).to.eq(0);
        expect(liquidatorTokenDetails.balance).to.eq(startLiquidatedTokenDetails.balance);
        expect(endLiquidatedBaseDetails.balance).to.eq(
          startLiquidatedBaseDetails.balance
            .add(startLiquidatedTokenDetails.balance.mul(liquidationPriceX128).div(1n << 128n))
            .sub(liquidationParams.fixFee),
        );
        expect(liquidatorBaseDetails.balance).to.eq(
          startLiquidatedTokenDetails.balance
            .mul(liquidatorPriceX128)
            .div(1n << 128n)
            .mul(-1)
            .add(liquidationParams.fixFee),
        );
      });

      it('Liquidation (Account Negative Afterwards)- Success', async () => {
        await test.addMargin(1, vBaseAddress, tokenAmount(1000, 6), constants);
        await changeVPoolPriceToNearestTick(5000);

        const startLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const startLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const startLiquidatedBaseDeposits = await test.getAccountDepositBalance(0, vBaseAddress);

        await test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants);

        const endLiquidatedTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const liquidatorTokenDetails = await test.getAccountTokenDetails(1, vTokenAddress);
        const endLiquidatedBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
        const liquidatorBaseDetails = await test.getAccountTokenDetails(1, vBaseAddress);

        const priceX128 = await priceToNearestPriceX128(5000, vBase, vToken);
        const liquidationPriceX128 = priceX128.add(priceX128.mul(300).div(10000));
        const liquidatorPriceX128 = priceX128.add(priceX128.mul(150).div(10000));

        expect(endLiquidatedTokenDetails.balance).to.eq(0);
        expect(liquidatorTokenDetails.balance).to.eq(startLiquidatedTokenDetails.balance);
        expect(endLiquidatedBaseDetails.balance).to.eq(startLiquidatedBaseDeposits.mul(-1));
        expect(liquidatorBaseDetails.balance).to.eq(
          startLiquidatedTokenDetails.balance
            .mul(liquidatorPriceX128)
            .div(1n << 128n)
            .mul(-1)
            .add(liquidationParams.fixFee),
        );
      });
    });
  });

  describe('Limit Order Removal', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumberish;
    before(async () => {
      tickLower = await priceToTick(4500, vBase, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(3500, vBase, vToken);
      tickUpper -= tickUpper % 10;
      liquidity = tokenAmount(1, 18);
    });
    beforeEach(async () => {
      await test.addMargin(0, vTokenAddress, tokenAmount(10000000, 6), constants);
    });
    afterEach(async () => {
      await test.cleanDeposits(0, constants);
      await test.cleanPositions(0, constants);
    });
    it('Limit Order Removal (Upper) with Fee - No Price Change', async () => {
      await changeVPoolWrapperFakePrice(3400);
      await changeVPoolPriceToNearestTick(3400);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 2);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 2, liquidity);

      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, tokenAmount(5, 6), constants);

      await checkTokenBalance(vTokenAddress, 0);
      await checkTokenBalance(vBaseAddress, tokenAmount(-5, 6));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Limit Order Removal (Lower) with Fee - No Price Change', async () => {
      await changeVPoolWrapperFakePrice(4600);
      await changeVPoolPriceToNearestTick(4600);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, tokenAmount(5, 6), constants);

      await checkTokenBalance(vTokenAddress, 0);
      await checkTokenBalance(vBaseAddress, tokenAmount(-5, 6));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });
    it('Limit Order Removal (Lower) with Fee - Price Change', async () => {
      await changeVPoolWrapperFakePrice(4000);
      await changeVPoolPriceToNearestTick(4000);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await changeVPoolWrapperFakePrice(4600);
      await changeVPoolPriceToNearestTick(4600);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(4600, vBase, vToken));
      await test.removeLimitOrder(0, vTokenAddress, tickLower, tickUpper, tokenAmount(5, 6), constants);
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );

      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkTokenBalance(vBaseAddress, startBaseDetails.balance.add(vBaseAmount).add(tokenAmount(-5, 6)));
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Limit Order Removal Fail - Inactive Range', async () => {
      await changeVPoolWrapperFakePrice(4000);
      await changeVPoolPriceToNearestTick(4000);

      await test.addMargin(0, vTokenAddress, tokenAmount(10000000, 6), constants);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 1);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 1, liquidity);

      await changeVPoolWrapperFakePrice(4600);
      await changeVPoolPriceToNearestTick(4600);

      expect(
        test.removeLimitOrder(0, vTokenAddress, tickLower - 10, tickUpper, tokenAmount(5, 6), constants),
      ).to.be.revertedWith('InactiveRange()');
    });
  });

  describe('#Single Range Position Liquidation', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumberish;
    let price: number;
    before(async () => {
      tickLower = await priceToTick(4500, vBase, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(3500, vBase, vToken);
      tickUpper -= tickUpper % 10;
      liquidity = tokenAmount(1, 18);
    });
    beforeEach(async () => {
      await changeVPoolWrapperFakePrice(3000);
      await changeVPoolPriceToNearestTick(3000);
      await test.addMargin(0, vTokenAddress, tokenAmount(1200000, 6), constants);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
    });
    it('Liquidation - Fail (Account Above Water)', async () => {
      const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        0,
        false,
        minRequiredMargin,
        constants,
      );
      expect(test.liquidateLiquidityPositions(0, liquidationParams, constants)).to.be.revertedWith(
        'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Liquidation - Success (Account Positive)', async () => {
      price = 4100;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );
      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(price, vBase, vToken));
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );

      await test.liquidateLiquidityPositions(0, liquidationParams, constants);

      const priceCurrentX128 = await priceToNearestPriceX128(price, vBase, vToken);
      const notionalAmountClosed = vBaseAmount.add(vTokenAmount.mul(priceCurrentX128).div(1n << 128n));
      const feeHalf = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5).div(2);
      expect(keeperFee).to.eq(feeHalf.add(liquidationParams.fixFee));
      expect(insuranceFundFee).to.eq(feeHalf);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmount).sub(feeHalf.mul(2)).sub(liquidationParams.fixFee),
      );
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Positive to Negative)', async () => {
      price = 4550;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );

      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(price, vBase, vToken));
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );
      await test.liquidateLiquidityPositions(0, liquidationParams, constants);

      const priceCurrentX128 = await priceToNearestPriceX128(price, vBase, vToken);
      const notionalAmountClosed = vBaseAmount.add(vTokenAmount.mul(priceCurrentX128).div(1n << 128n));

      const feeHalf = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5).div(2);
      const expectedKeeperFee = feeHalf.add(liquidationParams.fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(feeHalf.add(liquidationParams.fixFee));

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).lt(keeperFee);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmount).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Negative)', async () => {
      price = 4700;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );

      const sqrtPriceCurrent = tickToSqrtPriceX96(await priceToTick(price, vBase, vToken));
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );
      await test.liquidateLiquidityPositions(0, liquidationParams, constants);

      const priceCurrentX128 = await priceToNearestPriceX128(price, vBase, vToken);

      const notionalAmountClosed = vBaseAmount.add(vTokenAmount.mul(priceCurrentX128).div(1n << 128n));
      const feeHalf = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5).div(2);
      const expectedKeeperFee = feeHalf.add(liquidationParams.fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(feeHalf.add(liquidationParams.fixFee));

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).gt(keeperFee);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmount));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmount).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    afterEach(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
  });

  describe('#Multiple Range Position Liquidation', () => {
    let tickLower: number;
    let tickUpper: number;
    let tickLower1: number;
    let tickUpper1: number;
    let liquidity: BigNumberish;
    let price: number;
    before(async () => {
      tickLower = await priceToTick(4500, vBase, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(3500, vBase, vToken);
      tickUpper -= tickUpper % 10;
      tickLower1 = tickLower - 100;
      tickUpper1 = tickUpper + 100;
      liquidity = tokenAmount(1, 18).div(2);
    });
    beforeEach(async () => {
      await changeVPoolWrapperFakePrice(3000);
      await changeVPoolPriceToNearestTick(3000);
      await test.addMargin(0, vTokenAddress, tokenAmount(1250000, 6), constants);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
      await liquidityChange(tickLower1, tickUpper1, liquidity, false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 2);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
      await checkLiquidityPositionDetails(vTokenAddress, 1, tickLower1, tickUpper1, 0, liquidity);
    });
    it('Liquidation - Fail (Account Above Water)', async () => {
      const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        0,
        false,
        minRequiredMargin,
        constants,
      );
      expect(test.liquidateLiquidityPositions(0, liquidationParams, constants)).to.be.revertedWith(
        'InvalidLiquidationAccountAbovewater(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Liquidation - Success (Account Positive)', async () => {
      price = 4100;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );

      const { vBaseAmountTotal, vTokenAmountTotal, notionalAmountClosed } = await calculateNotionalAmountClosed(
        vTokenAddress,
        price,
      );

      await test.liquidateLiquidityPositions(0, liquidationParams, constants);
      const liquidationFee = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5);
      const expectedKeeperFee = liquidationFee
        .mul(1e4 - liquidationParams.insuranceFundFeeShareBps)
        .div(1e4)
        .add(liquidationParams.fixFee);
      const expectedInsuranceFundFee = liquidationFee.sub(keeperFee).add(liquidationParams.fixFee);

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmountTotal));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmountTotal).sub(liquidationFee).sub(liquidationParams.fixFee),
      );
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Positive to Negative)', async () => {
      price = 4550;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );

      const { vBaseAmountTotal, vTokenAmountTotal, notionalAmountClosed } = await calculateNotionalAmountClosed(
        vTokenAddress,
        price,
      );

      await test.liquidateLiquidityPositions(0, liquidationParams, constants);

      const liquidationFee = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5);
      const expectedKeeperFee = liquidationFee
        .mul(1e4 - liquidationParams.insuranceFundFeeShareBps)
        .div(1e4)
        .add(liquidationParams.fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(keeperFee);

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).lt(keeperFee);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmountTotal));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmountTotal).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    it('Liquidation - Success (Account Negative)', async () => {
      price = 4700;
      await changeVPoolWrapperFakePrice(price);
      await changeVPoolPriceToNearestTick(price);
      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      let startAccountMarketValue;
      {
        const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          0,
          false,
          minRequiredMargin,
          constants,
        );
        startAccountMarketValue = accountMarketValue;
      }

      const { keeperFee, insuranceFundFee } = await test.callStatic.liquidateLiquidityPositions(
        0,
        liquidationParams,
        constants,
      );

      const { vBaseAmountTotal, vTokenAmountTotal, notionalAmountClosed } = await calculateNotionalAmountClosed(
        vTokenAddress,
        price,
      );

      await test.liquidateLiquidityPositions(0, liquidationParams, constants);

      const liquidationFee = notionalAmountClosed.mul(liquidationParams.liquidationFeeFraction).div(1e5);
      const expectedKeeperFee = liquidationFee
        .mul(1e4 - liquidationParams.insuranceFundFeeShareBps)
        .div(1e4)
        .add(liquidationParams.fixFee);
      const expectedInsuranceFundFee = startAccountMarketValue.sub(keeperFee);

      expect(keeperFee).to.eq(expectedKeeperFee);
      expect(insuranceFundFee).to.eq(expectedInsuranceFundFee);
      expect(insuranceFundFee.abs()).gt(keeperFee);
      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.add(vTokenAmountTotal));
      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.add(vBaseAmountTotal).sub(expectedInsuranceFundFee.add(expectedKeeperFee)),
      );
      await checkAccountMarketValueAndRequiredMargin(false, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
    });

    afterEach(async () => {
      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
  });

  describe('#Trade- Liquidity Change', () => {
    let tickLower: number;
    let tickUpper: number;
    let liquidity: BigNumber;
    let netSumB: BigNumber;
    before(async () => {
      tickLower = await priceToTick(4500, vBase, vToken);
      tickLower -= tickLower % 10;
      tickUpper = await priceToTick(3500, vBase, vToken);
      tickUpper -= tickUpper % 10;
      netSumB = BigNumber.from(0);
    });

    beforeEach(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await changeVPoolWrapperFakePrice(4000);
      liquidity = tokenAmount(100000, 6);
      await test.addMargin(0, vBaseAddress, tokenAmount(100000, 6), constants);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);
    });

    afterEach(async () => {
      //Makes sumBInsideLast = 0
      setWrapperValuesInside(0);
      await liquidityChange(tickLower, tickUpper, 1, false, 0);

      await test.cleanPositions(0, constants);
      await test.cleanDeposits(0, constants);
    });
    it('Successful Add', async () => {
      const tick = await priceToTick(4000, vBase, vToken);
      const sqrtPriceCurrent = tickToSqrtPriceX96(tick);

      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );
      await checkTokenBalance(vTokenAddress, vTokenAmount.mul(-1));
      await checkTokenBalance(vBaseAddress, vBaseAmount.mul(-1));
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, tickLower, tickUpper, 0, liquidity);
      await checkAccountMarketValueAndRequiredMargin(false, liquidity);
    });

    it('Successful Remove (No Net Position)', async () => {
      liquidity = liquidity.mul(-1);
      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);

      await checkTokenBalance(vTokenAddress, 0);
      await checkTokenBalance(vBaseAddress, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
      await checkAccountMarketValueAndRequiredMargin(false, tokenAmount(100000, 6));
    });

    it('Successful Remove And Close (No Net Position)', async () => {
      liquidity = liquidity.mul(-1);
      await liquidityChange(tickLower, tickUpper, liquidity, true, 0);

      await checkTokenBalance(vTokenAddress, 0);
      await checkTokenBalance(vBaseAddress, 0);
      await checkLiquidityPositionNum(vTokenAddress, 0);
      await checkAccountMarketValueAndRequiredMargin(false, tokenAmount(100000, 6));
    });

    it('Successful Remove (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vBase, vToken);
      const sqrtPriceCurrent = tickToSqrtPriceX96(tick);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      liquidity = liquidity.mul(-1);
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );
      netSumB = startTokenDetails.balance
        .sub(vTokenAmount)
        .mul(-1)
        .mul(1n << 128n)
        .div(liquidity);
      setWrapperValuesInside(netSumB);

      await liquidityChange(tickLower, tickUpper, liquidity, false, 0);

      await checkTokenBalance(vTokenAddress, startTokenDetails.balance.sub(vTokenAmount));
      await checkTokenBalance(vBaseAddress, startBaseDetails.balance.sub(vBaseAmount));
      await checkTraderPosition(vTokenAddress, netSumB.mul(position.liquidity).div(1n << 128n));
      await checkLiquidityPositionNum(vTokenAddress, 0);
      // await checkAccountMarketValueAndRequiredMargin(false, tokenAmount(100000, 6));
    });

    it('Successful Remove And Close (Non-Zero Net Position)', async () => {
      const price = 4300;
      await changeVPoolPriceToNearestTick(price);
      await changeVPoolWrapperFakePrice(price);
      const tick = await priceToTick(price, vBase, vToken);
      const sqrtPriceCurrent = tickToSqrtPriceX96(tick);
      const priceX128Current = await priceToNearestPriceX128(price, vBase, vToken);

      const startTokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
      const startBaseDetails = await test.getAccountTokenDetails(0, vBaseAddress);
      const position = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, 0);

      liquidity = liquidity.mul(-1);
      const { vBaseAmount, vTokenAmount } = amountsForLiquidity(
        tickLower,
        sqrtPriceCurrent,
        tickUpper,
        liquidity,
        vBase,
        vToken,
      );
      netSumB = startTokenDetails.balance
        .sub(vTokenAmount)
        .mul(-1)
        .mul(1n << 128n)
        .div(liquidity);

      setWrapperValuesInside(netSumB);

      const netTraderPosition = netSumB.mul(position.liquidity).div(1n << 128n);

      await liquidityChange(tickLower, tickUpper, liquidity, true, 0);

      const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
      //TODO: !!!!! Check how to fix this !!!!!
      expect(vTokenPosition.balance.abs()).lte(1);
      expect(vTokenPosition.netTraderPosition.abs()).lte(1);

      await checkTokenBalance(
        vBaseAddress,
        startBaseDetails.balance.sub(vBaseAmount).add(netTraderPosition.mul(priceX128Current).div(1n << 128n)),
      );
      await checkLiquidityPositionNum(vTokenAddress, 0);
      // await checkAccountMarketValueAndRequiredMargin(false, tokenAmount(100000, 6));
    });
  });
});
