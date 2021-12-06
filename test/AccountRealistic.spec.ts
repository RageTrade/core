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
  let price: any;
  let vBaseAddress: string;
  let vToken: VToken;
  let minRequiredMargin: BigNumberish;

  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function changeVPoolPriceToNearestTick(price: number) {
    const tick = await priceToTick(price, vBase, vToken);
    vPoolFake.observe.returns([[0, tick * 60], []]);
  }

  async function checkTokenBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
  }

  async function checkDepositBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(vTokenAddress);
    expect(balance).to.eq(vTokenBalance);
  }

  async function checkAccountMarketValueAndRequiredMargin(
    isInitialMargin: boolean,
    expectedAccountMarketValue?: BigNumberish,
    expectedRequiredMargin?: BigNumberish,
  ) {
    const { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
      isInitialMargin,
      minRequiredMargin,
      constants,
    );
    if (typeof accountMarketValue !== 'undefined') expect(accountMarketValue).to.eq(expectedAccountMarketValue);
    if (typeof requiredMargin !== 'undefined') expect(requiredMargin).to.eq(expectedRequiredMargin);
  }

  async function checkLiquidityPositionNum(vTokenAddress: string, num: BigNumberish) {
    const outNum = await test.getAccountLiquidityPositionNum(vTokenAddress);
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
    const out = await test.getAccountLiquidityPositionDetails(vTokenAddress, num);
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

    price = await priceToNearestPriceX128(4000, vBase, vToken);

    vPoolWrapperFake.swapToken.returns((input: any) => {
      if (input.isNotional) {
        return [input.amount.mul(1n << 128n).div(price), -input.amount];
      } else {
        return [
          input.amount,
          input.amount
            .mul(price)
            .div(1n << 128n)
            .mul(-1),
        ];
      }
    });

    vPoolWrapperFake.liquidityChange.returns((input: any) => {
      return [-input.liquidity.mul(price).div(1n << 128n), -input.liquidity];
    });

    minRequiredMargin = tokenAmount(20, 6);
  });
  after(deactivateMainnetFork);
  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
    });
  });

  describe('#Margin', () => {
    it('Add Margin', async () => {
      await test.addMargin(vBaseAddress, tokenAmount(100, 6), constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(100, 6));
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(100, 6), minRequiredMargin);
    });
    it('Remove Margin - Fail', async () => {
      await changeVPoolPriceToNearestTick(4000);

      await test.swapTokenAmount(vTokenAddress, tokenAmount(1, 18).div(10), minRequiredMargin, constants);

      let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
        true,
        minRequiredMargin,
        constants,
      );
      accountMarketValue = accountMarketValue.sub(tokenAmount(50, 6));

      expect(test.removeMargin(vBaseAddress, tokenAmount(50, 6), minRequiredMargin, constants)).to.be.revertedWith(
        'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
      );
    });
    it('Remove Margin - Pass', async () => {
      test.cleanPositions(constants);
      await test.removeMargin(vBaseAddress, tokenAmount(50, 6), minRequiredMargin, constants);
      await checkDepositBalance(vBaseAddress, tokenAmount(50, 6));
      await checkAccountMarketValueAndRequiredMargin(true, tokenAmount(50, 6), minRequiredMargin);
    });
  });

  describe('#Trade - Swap Token Amount', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.cleanPositions(constants);
    });
    it('Successful Trade', async () => {
      const tokenBalance = tokenAmount(1, 18).div(10 ** 2);
      const baseBalance = tokenBalance
        .mul(price)
        .mul(-1)
        .div(1n << 128n);

      await test.swapTokenAmount(vTokenAddress, tokenBalance, minRequiredMargin, constants);
      await checkTokenBalance(vTokenAddress, tokenBalance);
      await checkTokenBalance(vBaseAddress, baseBalance);
    });
  });

  describe('#Trade - Swap Token Notional', () => {
    before(async () => {
      await changeVPoolPriceToNearestTick(4000);
      await test.cleanPositions(constants);
    });
    it('Successful Trade', async () => {
      const baseBalance = tokenAmount(50, 6);
      const tokenBalance = baseBalance.mul(1n << 128n).div(price);

      await test.swapTokenNotional(vTokenAddress, baseBalance, minRequiredMargin, constants);
      await checkTokenBalance(vTokenAddress, tokenBalance);
      await checkTokenBalance(vBaseAddress, baseBalance.mul(-1));
    });
  });

  describe('#Profit', () => {
    describe('#Token Position Profit', () => {
      before(async () => {
        await changeVPoolPriceToNearestTick(4000);
        await test.cleanPositions(constants);
        await test.addMargin(vBaseAddress, tokenAmount(50, 6), constants);
        await test.swapTokenAmount(vTokenAddress, tokenAmount(1, 18).div(10), minRequiredMargin, constants);
      });
      it('Remove Profit - Fail (No Profit | Enough Margin)', async () => {
        let profit = (await test.getAccountProfit(constants)).sub(tokenAmount(1, 6));
        expect(test.removeProfit(tokenAmount(1, 6), minRequiredMargin, constants)).to.be.revertedWith(
          'InvalidTransactionNotEnoughProfit(' + profit + ')',
        );
      });
      it('Remove Profit - Fail (Profit Available | Not Enough Margin)', async () => {
        await changeVPoolPriceToNearestTick(4020);
        await test.removeMargin(vBaseAddress, tokenAmount(21, 6), minRequiredMargin, constants);
        let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(
          true,
          minRequiredMargin,
          constants,
        );
        accountMarketValue = accountMarketValue.sub(tokenAmount(1, 6));
        expect(test.removeProfit(tokenAmount(1, 6), minRequiredMargin, constants)).to.be.revertedWith(
          'InvalidTransactionNotEnoughMargin(' + accountMarketValue + ', ' + requiredMargin + ')',
        );
      });
      it('Remove Profit - Pass', async () => {
        await changeVPoolPriceToNearestTick(4050);
        const baseDetails = await test.getAccountTokenDetails(vBaseAddress);
        await test.removeProfit(tokenAmount(1, 6), minRequiredMargin, constants);
        checkTokenBalance(vBaseAddress, baseDetails.balance.sub(tokenAmount(1, 6)));
      });
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

  describe('#Liquidation', () => {
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
    // describe('#Token Position Liquidation', () => {
    //   before(async () => {
    //     await changeVPoolPriceToNearestTick(4000);
    //     await test.cleanPositions(constants);
    //     await test.swapTokenNotional(vTokenAddress,tokenAmount())
    //     let { accountMarketValue, requiredMargin } = await test.getAccountValueAndRequiredMargin(false, tokenAmount(20,6), constants);
    //     console.log(accountMarketValue, requiredMargin);
    //   });
    //   it('Liquidation - Fail (Account Above Water)');
    //   it('Liquidation - Success');
    // });
  });
});
