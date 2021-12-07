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
} from './utils/price-tick';

describe('Account Library Test - 2', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  let constants: ConstantsStruct;
  let vTokenAddress: string;
  let clearingHouse: ClearingHouse;
  let vPoolFactory: VPoolFactory;

  let test: AccountTest;
  let realBase: FakeContract<ERC20>;
  let vBase: FakeContract<VBase>;
  let oracle: OracleMock;
  let vBaseAddress: string;
  let vToken: VToken;
  let minRequiredMargin: BigNumberish;
  let liquidationFeeFraction: BigNumberish;
  let liquidationParams: any;

  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function changeVPoolPriceToNearestTick(price: number) {
    const tick = await priceToTick(price, vBase, vToken);
    vPoolFake.observe.returns([[0, tick * 60], []]);
  }

  async function changeVPoolWrapperFakePrice(price: number) {
    const priceX128 = await priceToNearestPriceX128(price, vBase, vToken);

    vPoolWrapperFake.swapToken.returns((input: any) => {
      if (input.isNotional) {
        return [input.amount.mul(1n << 128n).div(priceX128), -input.amount];
      } else {
        return [
          input.amount,
          input.amount
            .mul(priceX128)
            .div(1n << 128n)
            .mul(-1),
        ];
      }
    });

    vPoolWrapperFake.liquidityChange.returns((input: any) => {
      return [
        input.liquidity
          .mul(priceX128)
          .div(1n << 128n)
          .mul(-1),
        input.liquidity.mul(-1),
      ];
    });
  }

  async function checkTokenBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
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
    if (typeof accountMarketValue !== 'undefined') expect(accountMarketValue).to.eq(expectedAccountMarketValue);
    if (typeof requiredMargin !== 'undefined') expect(requiredMargin).to.eq(expectedRequiredMargin);
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
    sumALast?: BigNumberish,
    sumBInsideLast?: BigNumberish,
    sumFpInsideLast?: BigNumberish,
    longsFeeGrowthInsideLast?: BigNumberish,
    shortsFeeGrowthInsideLast?: BigNumberish,
  ) {
    const out = await test.getAccountLiquidityPositionDetails(0, vTokenAddress, num);
    if (typeof tickLower !== 'undefined') expect(out.tickLower).to.eq(tickLower);
    if (typeof tickUpper !== 'undefined') expect(out.tickUpper).to.eq(tickUpper);
    if (typeof limitOrderType !== 'undefined') expect(out.limitOrderType).to.eq(limitOrderType);
    if (typeof liquidity !== 'undefined') expect(out.liquidity).to.eq(liquidity);
    if (typeof sumALast !== 'undefined') expect(out.sumALast).to.eq(sumALast);
    if (typeof sumBInsideLast !== 'undefined') expect(out.sumBInsideLast).to.eq(sumBInsideLast);
    if (typeof sumFpInsideLast !== 'undefined') expect(out.sumFpInsideLast).to.eq(sumFpInsideLast);
    if (typeof longsFeeGrowthInsideLast !== 'undefined')
      expect(out.longsFeeGrowthInsideLast).to.eq(longsFeeGrowthInsideLast);
    if (typeof shortsFeeGrowthInsideLast !== 'undefined')
      expect(out.shortsFeeGrowthInsideLast).to.eq(shortsFeeGrowthInsideLast);
  }

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;

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

    const factory = await hre.ethers.getContractFactory('AccountTest');
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
    });
  });

  describe('#Margin', () => {
    it('Add Margin', async () => {
      await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(100, 6));
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(100, 6), minRequiredMargin);
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
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(50, 6), minRequiredMargin);
    });
  });

  describe('#Profit', () => {
    describe('#Token Position Profit', () => {
      before(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.cleanPositions(0, constants);
        await test.addMargin(0, vBaseAddress, tokenAmount(50, 6), constants);
        await test.swapTokenAmount(0, vTokenAddress, tokenAmount(1, 18).div(10), minRequiredMargin, constants);
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
      await test.cleanPositions(0, constants);
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
      await test.cleanPositions(0, constants);
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
  // it('Liqudity Change', async () => {
  //   await test.cleanPositions(constants);
  //   await checkTokenBalance(vTokenAddress, '0');

  //   await test.liquidityChange(vTokenAddress, -100, 100, 5, 0, tokenAmount(20,6), constants);
  //   await checkTokenBalance(vTokenAddress, '-5');
  //   await checkTokenBalance(vBaseAddress, -20000);
  //   await checkLiquidityPositionNum(vTokenAddress, 1);
  //   await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 0, 5);
  // });

  // describe('#Range Position Liquidation', () => {
  //   before(async () => {
  //     await changeVPoolPriceToNearestTick(4000);
  //     await test.cleanPositions(constants);
  //     const tickLower = await priceToTick(3500, vBase, vToken);
  //     const tickUpper = await priceToTick(4500, vBase, vToken);
  //     await test.liquidityChange(vTokenAddress, tickLower, tickUpper, 100, 0, tokenAmount(20,6), constants);
  //     let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(false, tokenAmount(20,6), constants);
  //     console.log(accountMarketValue, requiredMargin);
  //   });
  //   it('Liquidation - Fail (Account Above Water)');
  //   it('Liquidation - Success');
  // });

  describe('#Token Liquidation', () => {
    describe('#Token Position Liquidation Helpers', () => {
      it('Liquidation Price at 4000 ', async () => {
        const tokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);
        const priceX128 = await priceToNearestPriceX128(4000, vBase, vToken);
        const { liquidationPriceX128, liquidatorPriceX128 } = await test.getLiquidationPriceX128(
          tokenDetails.balance,
          vTokenAddress,
          liquidationParams,
          constants,
        );
        expect(liquidationPriceX128).to.eq(priceX128.sub(priceX128.mul(300).div(10000)));
        expect(liquidatorPriceX128).to.eq(priceX128.sub(priceX128.mul(150).div(10000)));
      });
      it('Liquidation Price at 3500 ', async () => {
        await changeVPoolPriceToNearestTick(3500);
        const tokenDetails = await test.getAccountTokenDetails(0, vTokenAddress);

        const priceX128 = await priceToNearestPriceX128(3500, vBase, vToken);
        const { liquidationPriceX128, liquidatorPriceX128 } = await test.getLiquidationPriceX128(
          tokenDetails.balance,
          vTokenAddress,
          liquidationParams,
          constants,
        );

        expect(liquidationPriceX128).to.eq(priceX128.sub(priceX128.mul(300).div(10000)));
        expect(liquidatorPriceX128).to.eq(priceX128.sub(priceX128.mul(150).div(10000)));
      });
    });

    describe('#Token Position Liquidation Scenarios', () => {
      before(async () => {
        await test.cleanDeposits(0, constants);
        await test.cleanPositions(0, constants);
        await changeVPoolPriceToNearestTick(4000);
        await test.addMargin(0, vBaseAddress, tokenAmount(100, 6), constants);

        const baseBalance = tokenAmount(500, 6);

        await test.swapTokenNotional(0, vTokenAddress, baseBalance, minRequiredMargin, constants);
        // let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        //   false,
        //   minRequiredMargin,
        //   constants,
        // );
        // checkAccountMarketValueAndRequiredMargin()
        // console.log(accountMarketValue.toBigInt(), requiredMargin.toBigInt());
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
        await test.addMargin(0, vTokenAddress, tokenAmount(1000, 6), constants);
        let liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: tokenAmount(1, 18),
          sqrtPriceCurrent: 0,
          slippageTolerance: 0,
          closeTokenPosition: false,
          limitOrderType: 0,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams, 0, constants);

        await changeVPoolPriceToNearestTick(3500);

        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
          'InvalidLiquidationActiveRangePresent("' + vTokenAddress + '")',
        );

        liquidityChangeParams.liquidityDelta = liquidityChangeParams.liquidityDelta.mul(-1);
        await changeVPoolPriceToNearestTick(4000);

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams, 0, constants);
        await test.removeMargin(0, vTokenAddress, tokenAmount(1000, 6), minRequiredMargin, constants);
      });
      it('Liquidation - Fail (Liquidator Not Enough Margin)', async () => {
        await changeVPoolPriceToNearestTick(3500);
        // expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.revertedWith(
        //   'InvalidTransactionNotEnoughMargin()',
        // );
        expect(test.liquidateTokenPosition(0, 1, vTokenAddress, liquidationParams, constants)).to.be.reverted;
      });
      it('Liquidation - Success', async () => {
        await test.addMargin(1, vBaseAddress, tokenAmount(1000, 6), constants);
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
        // let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        //   0,
        //   false,
        //   tokenAmount(20, 6),
        //   constants,
        // );
        // console.log(accountMarketValue.toBigInt(), requiredMargin.toBigInt());
      });
    });
  });
});
