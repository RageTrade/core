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
  RageTradeFactory,
  ClearingHouse,
} from '../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetupBase, testSetupToken } from './utils/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { tokenAmount } from './utils/stealFunds';

describe('Account Library Test Basic', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  // let constants: ConstantsStruct;
  let vTokenAddress: string;
  let clearingHouse: ClearingHouse;
  let rageTradeFactory: RageTradeFactory;

  let test: AccountTest;
  let realBase: FakeContract<ERC20>;
  let vBase: VBase;
  let oracle: OracleMock;
  let rBaseOracle: OracleMock;

  let vBaseAddress: string;

  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;

  let signers: SignerWithAddress[];

  async function checkTokenBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(0, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
  }

  async function checkDepositBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(0, vTokenAddress);
    expect(balance).to.eq(vTokenBalance);
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

    ({ realBase, vBase, clearingHouse, rageTradeFactory, oracle: rBaseOracle } = await testSetupBase());

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
      rageTradeFactory,
    }));

    vBaseAddress = vBase.address;

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

    vPoolWrapperFake.swapToken.returns((input: any) => {
      if (input.isNotional) {
        return [input.amount.mul(-1).div(4000), input.amount];
      } else {
        return [input.amount.mul(-1), input.amount.mul(4000)];
      }
    });

    vPoolWrapperFake.liquidityChange.returns((input: any) => {
      return [
        input.liquidityDelta * 4000,
        input.liquidityDelta,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ];
    });

    const liquidationParams = {
      liquidationFeeFraction: 1500,
      tokenLiquidationPriceDeltaBps: 3000,
      insuranceFundFeeShareBps: 5000,
    };
    const fixFee = tokenAmount(10, 6);
    const removeLimitOrderFee = tokenAmount(10, 6);
    const minimumOrderNotional = tokenAmount(1, 6).div(100);
    const minRequiredMargin = tokenAmount(20, 6);

    await test.setAccountStorage(
      liquidationParams,
      removeLimitOrderFee,
      minimumOrderNotional,
      minRequiredMargin,
      fixFee,
    );

    const poolObj = await clearingHouse.pools(vBase.address);
    await test.registerPool(vBase.address, poolObj);

    const poolObj2 = await clearingHouse.pools(vTokenAddress);
    await test.registerPool(vTokenAddress, poolObj2);

    await test.setVBaseAddress(vBase.address);
  });
  after(deactivateMainnetFork);
  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
      test.initCollateral(realBase.address, rBaseOracle.address, 300);
    });
  });

  describe('#Margin', () => {
    it('Add Margin', async () => {
      await test.addMargin(0, realBase.address, '10000000000');
      await checkDepositBalance(realBase.address, '10000000000');
    });

    it('Remove Margin', async () => {
      await test.removeMargin(0, realBase.address, '50');
      await checkDepositBalance(realBase.address, '9999999950');
    });
  });

  describe('#Trades', () => {
    before(async () => {});
    it('Swap Token (Token Amount)', async () => {
      await test.swapTokenAmount(0, vTokenAddress, '10');
      await checkTokenBalance(vTokenAddress, '10');
      await checkTokenBalance(vBase.address, -40000);
    });

    it('Swap Token (Token Notional)', async () => {
      await test.swapTokenNotional(0, vTokenAddress, '40000');
      await checkTokenBalance(vTokenAddress, '20');
      await checkTokenBalance(vBaseAddress, -80000);
    });

    it('Liqudity Change', async () => {
      await test.cleanPositions(0);
      await checkTokenBalance(vTokenAddress, '0');

      const liquidityChangeParams = {
        tickLower: -100,
        tickUpper: 100,
        liquidityDelta: 5,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
        closeTokenPosition: false,
        limitOrderType: 0,
      };
      await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
      await checkTokenBalance(vTokenAddress, '-5');
      await checkTokenBalance(vBaseAddress, -20000);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 0, 5);
    });
  });

  describe('#Remove Limit Order', () => {
    describe('Not limit order', () => {
      before(async () => {
        await test.cleanPositions(0);
        const liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: 5,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 0,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 0, 5);
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
          liquidityDelta: 5,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 1,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 1, 5);
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
        await checkTokenBalance(vTokenAddress, 0);
        await checkTokenBalance(vBaseAddress, 0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
    describe('Upper limit order', () => {
      before(async () => {
        await test.cleanPositions(0);
        const liquidityChangeParams = {
          tickLower: 194000,
          tickUpper: 195000,
          liquidityDelta: 5,
          sqrtPriceCurrent: 0,
          slippageToleranceBps: 0,
          closeTokenPosition: false,
          limitOrderType: 2,
        };

        await test.liquidityChange(0, vTokenAddress, liquidityChangeParams);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, 194000, 195000, 2, 5);
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
        await checkTokenBalance(vTokenAddress, 0);
        await checkTokenBalance(vBaseAddress, 0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
  });

  describe('#Liquidation', () => {
    const liquidationParams = {
      fixFee: tokenAmount(10, 6),
      minRequiredMargin: tokenAmount(20, 6),
      liquidationFeeFraction: 150,
      tokenLiquidationPriceDeltaBps: 300,
      insuranceFundFeeShareBps: 5000,
    };
    it('Liquidate Liquidity Positions - Fail', async () => {
      expect(test.liquidateLiquidityPositions(0)).to.be.reverted; // feeFraction=15/10=1.5
    });
    it('Liquidate Token Positions - Fail', async () => {
      expect(test.liquidateTokenPosition(0, 1, vTokenAddress)).to.be.reverted;
    });
  });
});
