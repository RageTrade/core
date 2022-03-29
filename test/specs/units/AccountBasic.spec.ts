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
} from '../../../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetupVQuote, testSetupToken } from '../../utils/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from '../../utils/mainnet-fork';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { parseTokenAmount } from '../../utils/stealFunds';
import { truncate } from '../../utils/vToken';

describe('Account Library Test Basic', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  // let constants: ConstantsStruct;
  let vTokenAddress: string;
  let clearingHouse: ClearingHouse;
  let rageTradeFactory: RageTradeFactory;

  let test: AccountTest;
  let settlementToken: FakeContract<ERC20>;
  let vQuote: VQuote;
  let oracle: OracleMock;
  let settlementTokenOracle: OracleMock;

  let vQuoteAddress: string;

  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function checkVTokenBalance(vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vVTokenBalance);
  }

  async function checkVQuoteBalance(vQuoteBalance: BigNumberish) {
    const vQuoteBalance_ = await test.getAccountQuoteBalance(0);
    expect(vQuoteBalance_).to.eq(vQuoteBalance);
  }

  async function checkDepositBalance(vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(0, vTokenAddress);
    expect(balance).to.eq(vVTokenBalance);
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

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;

    ({
      settlementToken,
      vQuote,
      clearingHouse,
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
    vPoolWrapperFake.vPool.returns(vPoolFake.address);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const factory = await hre.ethers.getContractFactory('AccountTest', {
      libraries: {
        Account: accountLib.address,
      },
    });
    test = await factory.deploy();

    vPoolWrapperFake.swap.returns((input: any) => {
      if (input.amountSpecified.gt(0) === input.swapVTokenForVQuote) {
        return [
          {
            amountSpecified: input.amountSpecified,
            vTokenIn: input.amountSpecified,
            vQuoteIn: input.amountSpecified.mul(-1).mul(4000),
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
            vTokenIn: input.amountSpecified.mul(-1).div(4000),
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
      return [
        input.liquidity,
        input.liquidity.mul(4000),
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ];
    });
    vPoolWrapperFake.burn.returns((input: any) => {
      return [
        input.liquidity,
        input.liquidity.mul(4000),
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ];
    });

    const liquidationParams = {
      rangeLiquidationFeeFraction: 1500,
      tokenLiquidationFeeFraction: 3000,
      insuranceFundFeeShareBps: 5000,
      maxRangeLiquidationFees: 100000000,
      closeFactorMMThresholdBps: 7500,
      partialLiquidationCloseFactorBps: 5000,
      liquidationSlippageSqrtToleranceBps: 150,
      minNotionalLiquidatable: 100000000,
    };
    const fixFee = parseTokenAmount(0, 6);
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

    const poolObj = await clearingHouse.getPoolInfo(truncate(vQuote.address));
    await test.registerPool(poolObj);

    const poolObj2 = await clearingHouse.getPoolInfo(truncate(vTokenAddress));
    await test.registerPool(poolObj2);

    await test.setVQuoteAddress(vQuote.address);
  });
  after(deactivateMainnetFork);
  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
      test.initCollateral(settlementToken.address, settlementTokenOracle.address, 300);
    });
  });

  describe('#Margin', () => {
    it('Add Margin', async () => {
      await test.addMargin(0, settlementToken.address, '10000000000');
      await checkDepositBalance(settlementToken.address, '10000000000');
    });

    it('Remove Margin', async () => {
      await test.removeMargin(0, settlementToken.address, '50');
      await checkDepositBalance(settlementToken.address, '9999999950');
    });
  });

  describe('#Trades', () => {
    before(async () => {});
    it('Swap Token (Token Amount)', async () => {
      await test.swapTokenAmount(0, vTokenAddress, '10');
      await checkVTokenBalance(vTokenAddress, '10');
      await checkVQuoteBalance(-40000);
    });

    it('Swap Token (Token Notional)', async () => {
      await test.swapTokenNotional(0, vTokenAddress, '40000');
      await checkVTokenBalance(vTokenAddress, '20');
      await checkVQuoteBalance(-80000);
    });

    it('Liqudity Change', async () => {
      await test.cleanPositions(0);
      await checkVTokenBalance(vTokenAddress, '0');

      const liquidityChangeParams = {
        tickLower: -100,
        tickUpper: 100,
        liquidityDelta: 1,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
        closeTokenPosition: false,
        limitOrderType: 0,
      };
      await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
      await checkVTokenBalance(vTokenAddress, '-1');
      await checkVQuoteBalance(-4000);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 0, 1);
    });
  });

  describe('#Remove Limit Order', () => {
    describe('Not limit order', () => {
      before(async () => {
        await test.cleanPositions(0);
        const liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: 1,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 0,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkVTokenBalance(vTokenAddress, '-1');
        await checkVQuoteBalance(-4000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 0, 1);
      });
      it('Remove Failure - Inside Range (No Limit)', async () => {
        vPoolFake.observe.returns([[0, 194500 * 60], []]);
        vPoolFake.slot0.returns([0, 194500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Below Range (No Limit)', async () => {
        vPoolFake.observe.returns([[0, 193500 * 60], []]);
        vPoolFake.slot0.returns([0, 193500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Above Range (No Limit)', async () => {
        vPoolFake.observe.returns([[0, 195500 * 60], []]);
        vPoolFake.slot0.returns([0, 195500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
    });
    describe('Lower limit order', () => {
      before(async () => {
        await test.cleanPositions(0);
        const liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: 1,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 1,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkVTokenBalance(vTokenAddress, '-1');
        await checkVQuoteBalance(-4000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 1, 1);
      });
      it('Remove Failure - Inside Range (Lower Limit)', async () => {
        vPoolFake.observe.returns([[0, 194500 * 60], []]);
        vPoolFake.slot0.returns([0, 194500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Above Range (Lower Limit)', async () => {
        vPoolFake.observe.returns([[0, 195500 * 60], []]);
        vPoolFake.slot0.returns([0, 195500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Success - Below Range (Lower Limit)', async () => {
        vPoolFake.observe.returns([[0, 193500 * 60], []]);
        vPoolFake.slot0.returns([0, 193500, 0, 0, 0, 0, false]);

        test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0);
        await checkVTokenBalance(vTokenAddress, 0);
        await checkVQuoteBalance(0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
    describe('Upper limit order', () => {
      before(async () => {
        await test.cleanPositions(0);
        const liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: 1,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 2,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkVTokenBalance(vTokenAddress, '-1');
        await checkVQuoteBalance(-4000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 2, 1);
      });
      it('Remove Failure - Inside Range (Upper Limit)', async () => {
        vPoolFake.observe.returns([[0, 194500 * 60], []]);
        vPoolFake.slot0.returns([0, 194500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Below Range (Upper Limit)', async () => {
        vPoolFake.observe.returns([[0, 193500 * 60], []]);
        vPoolFake.slot0.returns([0, 193500, 0, 0, 0, 0, false]);

        await expect(test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Success - Above Range (Upper Limit)', async () => {
        vPoolFake.observe.returns([[0, 195500 * 60], []]);
        vPoolFake.slot0.returns([0, 195500, 0, 0, 0, 0, false]);

        test.removeLimitOrder(0, vTokenAddress, 194000, 195000, 0);
        await checkVTokenBalance(vTokenAddress, 0);
        await checkVQuoteBalance(0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
  });

  describe('#Liquidation', () => {
    const liquidationParams = {
      fixFee: parseTokenAmount(10, 6),
      minRequiredMargin: parseTokenAmount(20, 6),
      liquidationFeeFraction: 150,
      tokenLiquidationPriceDeltaBps: 300,
      insuranceFundFeeShareBps: 5000,
    };
    it('Liquidate Liquidity Positions - Fail', async () => {
      expect(test.liquidateLiquidityPositions(0)).to.be.reverted; // feeFraction=15/10=1.5
    });
    it('Liquidate Token Positions - Fail', async () => {
      expect(test.liquidateTokenPosition(1, vTokenAddress)).to.be.reverted;
    });
  });
});
