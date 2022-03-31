import { expect } from 'chai';
import { config } from 'dotenv';
import { ContractReceipt, ContractTransaction, ethers } from 'ethers';
import hre, { network } from 'hardhat';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  getCreateAddressFor,
  parseTokenAmount,
  priceToSqrtPriceX96,
  tickToSqrtPriceX96,
  truncate,
} from '@ragetrade/sdk';

import {
  Account__factory,
  ClearingHouseTest,
  IERC20,
  IUniswapV3Pool,
  OracleMock,
  RageTradeFactory,
  RealTokenMock,
  VPoolWrapperMockRealistic,
  VQuote,
  VToken,
} from '../../typechain-types';
import {
  TokenPositionChangedEvent,
  TokenPositionFundingPaymentRealizedEvent,
} from '../../typechain-types/artifacts/contracts/libraries/Account';
import { activateMainnetFork, deactivateMainnetFork } from '../helpers/mainnet-fork';
import { SETTLEMENT_TOKEN } from '../helpers/real-constants';
import { stealFunds } from '../helpers/steal-funds';

const whaleFosettlementToken = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

config();
const { ALCHEMY_KEY } = process.env;

describe('Clearing House Scenario 1 (Base swaps and liquidity changes)', () => {
  let vQuoteAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  // let constants: ConstantsStruct;
  let clearingHouseTest: ClearingHouseTest;
  let vPool: IUniswapV3Pool;
  let vPoolWrapper: VPoolWrapperMockRealistic;
  let vToken: VToken;
  let vQuote: VQuote;

  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user0: SignerWithAddress;
  let user1: SignerWithAddress;
  let user0AccountNo: BigNumberish;
  let user1AccountNo: BigNumberish;
  let user2: SignerWithAddress;
  let user2AccountNo: BigNumberish;

  let settlementToken: IERC20;
  let settlementTokenOracle: OracleMock;

  let vTokenAddress: string;
  let vTokenAddress1: string;
  let dummyTokenAddress: string;

  let oracle: OracleMock;
  let oracle1: OracleMock;

  let realToken: RealTokenMock;
  let realToken1: RealTokenMock;
  let initialBlockTimestamp: number;

  function X128ToDecimal(numX128: BigNumber, numDecimals: bigint) {
    return numX128.mul(10n ** numDecimals).div(1n << 128n);
  }
  async function closeTokenPosition(user: SignerWithAddress, accountNo: BigNumberish, vTokenAddress: string) {
    const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
    const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);

    const swapParams = {
      amount: accountTokenPosition.balance.mul(-1),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false,
    };
    await clearingHouseTest.connect(user).swapToken(accountNo, truncatedAddress, swapParams);
  }

  async function checkVirtualTick(expectedTick: number) {
    const { tick } = await vPool.slot0();
    expect(tick).to.eq(expectedTick);
  }

  async function checkVTokenBalance(accountNo: BigNumberish, vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vVTokenBalance);
  }

  async function checkVQuoteBalance(accountNo: BigNumberish, vQuoteBalance: BigNumberish) {
    const vQuoteBalance_ = await clearingHouseTest.getAccountQuoteBalance(accountNo);
    expect(vQuoteBalance_).to.eq(vQuoteBalance);
  }

  async function checkVTokenBalanceApproxiate(
    accountNo: BigNumberish,
    vTokenAddress: string,
    vVTokenBalance: BigNumberish,
    digitsToApproximate: BigNumberish,
  ) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.balance.sub(vVTokenBalance).abs()).lt(BigNumber.from(10).pow(digitsToApproximate));
  }

  async function checkTraderPosition(accountNo: BigNumberish, vTokenAddress: string, traderPosition: BigNumberish) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.netTraderPosition).to.eq(traderPosition);
  }

  async function checkDepositBalance(accountNo: BigNumberish, vTokenAddress: string, vVTokenBalance: BigNumberish) {
    const balance = await clearingHouseTest.getAccountDepositBalance(accountNo, vTokenAddress);
    expect(balance).to.eq(vVTokenBalance);
  }

  async function checkSettlementVTokenBalance(address: string, vTokenAmount: BigNumberish) {
    expect(await settlementToken.balanceOf(address)).to.eq(vTokenAmount);
  }

  async function checkLiquidityPositionNum(accountNo: BigNumberish, vTokenAddress: string, num: BigNumberish) {
    const outNum = await clearingHouseTest.getAccountLiquidityPositionNum(accountNo, vTokenAddress);
    expect(outNum).to.eq(num);
  }

  async function checkLiquidityPositionDetails(
    accountNo: BigNumberish,
    vTokenAddress: string,
    num: BigNumberish,
    tickLower?: BigNumberish,
    tickUpper?: BigNumberish,
    limitOrderType?: BigNumberish,
    liquidity?: BigNumberish,
    sumALast?: BigNumberish,
    sumBInsideLast?: BigNumberish,
    sumFpInsideLast?: BigNumberish,
    sumFeeInsideLast?: BigNumberish,
  ) {
    const out = await clearingHouseTest.getAccountLiquidityPositionDetails(accountNo, vTokenAddress, num);
    if (typeof tickLower !== 'undefined') expect(out.tickLower).to.eq(tickLower);
    if (typeof tickUpper !== 'undefined') expect(out.tickUpper).to.eq(tickUpper);
    if (typeof limitOrderType !== 'undefined') expect(out.limitOrderType).to.eq(limitOrderType);
    if (typeof liquidity !== 'undefined') expect(out.liquidity).to.eq(liquidity);
    if (typeof sumALast !== 'undefined') expect(X128ToDecimal(out.sumALastX128, 10n)).to.eq(sumALast);
    if (typeof sumBInsideLast !== 'undefined') expect(X128ToDecimal(out.sumBInsideLastX128, 10n)).to.eq(sumBInsideLast);
    if (typeof sumFpInsideLast !== 'undefined')
      expect(X128ToDecimal(out.sumFpInsideLastX128, 10n)).to.eq(sumFpInsideLast);
    if (typeof sumFeeInsideLast !== 'undefined')
      expect(X128ToDecimal(out.sumFeeInsideLastX128, 10n)).to.eq(sumFeeInsideLast);
  }

  async function addMargin(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    vTokenAmount: BigNumberish,
  ) {
    await settlementToken.connect(user).approve(clearingHouseTest.address, vTokenAmount);
    const truncatedVQuoteAddress = await clearingHouseTest.getTruncatedTokenAddress(tokenAddress);
    await clearingHouseTest.connect(user).updateMargin(userAccountNo, truncatedVQuoteAddress, vTokenAmount);
  }

  async function swapToken(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    amount: BigNumberish,
    sqrtPriceLimit: BigNumberish,
    isNotional: boolean,
    isPartialAllowed: boolean,
  ): Promise<ContractTransaction> {
    const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(tokenAddress);
    const swapParams = {
      amount: amount,
      sqrtPriceLimit: sqrtPriceLimit,
      isNotional: isNotional,
      isPartialAllowed: isPartialAllowed,
    };
    return await clearingHouseTest.connect(user).swapToken(userAccountNo, truncatedAddress, swapParams);
  }

  async function checkTokenPositionChangeEvent(
    txnReceipt: ContractReceipt,
    expectedUserAccountNo: BigNumberish,
    expectedTokenAddress: string,
    expectedTokenAmountOut: BigNumberish,
    expectedVQuoteAmountOut: BigNumberish,
  ) {
    const eventList = txnReceipt.logs
      ?.map(log => {
        try {
          return {
            ...log,
            ...Account__factory.connect(ethers.constants.AddressZero, hre.ethers.provider).interface.parseLog(log),
          };
        } catch {
          return null;
        }
      })
      .filter(event => event !== null)
      .filter(event => event?.name === 'TokenPositionChanged') as unknown as TokenPositionChangedEvent[];

    const event = eventList[0];
    expect(event.args.accountId).to.eq(expectedUserAccountNo);
    expect(event.args.poolId).to.eq(Number(truncate(expectedTokenAddress)));
    expect(event.args.vTokenAmountOut).to.eq(expectedTokenAmountOut);
    expect(event.args.vQuoteAmountOut).to.eq(expectedVQuoteAmountOut);
  }

  async function checkFundingPaymentEvent(
    txnReceipt: ContractReceipt,
    expectedUserAccountNo: BigNumberish,
    expectedTokenAddress: string,
    expectedFundingPayment: BigNumberish,
  ) {
    const eventList = txnReceipt.logs
      ?.map(log => {
        try {
          return {
            ...log,
            ...Account__factory.connect(ethers.constants.AddressZero, hre.ethers.provider).interface.parseLog(log),
          };
        } catch {
          return null;
        }
      })
      .filter(event => event !== null)
      .filter(
        event => event?.name === 'TokenPositionFundingPaymentRealized',
      ) as unknown as TokenPositionFundingPaymentRealizedEvent[];

    const event = eventList[0];

    expect(event.args.accountId).to.eq(expectedUserAccountNo);
    expect(event.args.poolId).to.eq(Number(truncate(expectedTokenAddress)));
    expect(event.args.amount).to.eq(expectedFundingPayment);
  }

  async function checkSwapEvents(
    swapTxn: ContractTransaction,
    expectedUserAccountNo: BigNumberish,
    expectedTokenAddress: string,
    expectedTokenAmountOut: BigNumberish,
    expectedVQuoteAmountOutWithFee: BigNumberish,
    expectedFundingPayment: BigNumberish,
  ) {
    const swapReceipt = await swapTxn.wait();

    await checkTokenPositionChangeEvent(
      swapReceipt,
      expectedUserAccountNo,
      expectedTokenAddress,
      expectedTokenAmountOut,
      expectedVQuoteAmountOutWithFee,
    );
    await checkFundingPaymentEvent(swapReceipt, expectedUserAccountNo, expectedTokenAddress, expectedFundingPayment);
  }

  async function swapTokenAndCheck(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    vQuoteAddress: string,
    amount: BigNumberish,
    sqrtPriceLimit: BigNumberish,
    isNotional: boolean,
    isPartialAllowed: boolean,
    expectedStartTick: number,
    expectedEndTick: number,
    expectedEndVTokenBalance: BigNumberish,
    expectedEndVQuoteBalance: BigNumberish,
    expectedTokenAmountOut: BigNumberish,
    expectedVQuoteAmountOutWithFee: BigNumberish,
    expectedFundingPayment: BigNumberish,
  ): Promise<ContractTransaction> {
    await checkVirtualTick(expectedStartTick);
    const swapTxn = await swapToken(
      user,
      userAccountNo,
      tokenAddress,
      amount,
      sqrtPriceLimit,
      isNotional,
      isPartialAllowed,
    );
    await checkVirtualTick(expectedEndTick);
    await checkVTokenBalance(user2AccountNo, tokenAddress, expectedEndVTokenBalance);
    await checkVQuoteBalance(user2AccountNo, expectedEndVQuoteBalance);
    await checkSwapEvents(
      swapTxn,
      userAccountNo,
      tokenAddress,
      expectedTokenAmountOut,
      expectedVQuoteAmountOutWithFee,
      expectedFundingPayment,
    );
    return swapTxn;
  }

  async function checkUnrealizedFundingPaymentAndFee(
    userAccountNo: BigNumberish,
    tokenAddress: string,
    num: BigNumberish,
    expectedUnrealizedFundingPayment: BigNumberish,
    expectedUnrealizedFee: BigNumberish,
  ) {
    const out = await clearingHouseTest.getAccountLiquidityPositionFundingAndFee(userAccountNo, tokenAddress, num);
    expect(out.unrealizedLiquidityFee).to.eq(expectedUnrealizedFee);
    expect(out.fundingPayment).to.eq(expectedUnrealizedFundingPayment);
  }

  async function updateRangeOrder(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    tickLower: BigNumberish,
    tickUpper: BigNumberish,
    liquidityDelta: BigNumberish,
    closeTokenPosition: boolean,
    limitOrderType: number,
  ) {
    const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(tokenAddress);

    let liquidityChangeParams = {
      tickLower: tickLower,
      tickUpper: tickUpper,
      liquidityDelta: liquidityDelta,
      sqrtPriceCurrent: 0,
      slippageToleranceBps: 0,
      closeTokenPosition: closeTokenPosition,
      limitOrderType: limitOrderType,
    };

    await clearingHouseTest.connect(user).updateRangeOrder(userAccountNo, truncatedAddress, liquidityChangeParams);
  }

  async function updateRangeOrderAndCheck(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    vQuoteAddress: string,
    tickLower: BigNumberish,
    tickUpper: BigNumberish,
    liquidityDelta: BigNumberish,
    closeTokenPosition: boolean,
    limitOrderType: number,
    liquidityPositionNum: BigNumberish,
    expectedEndLiquidityPositionNum: BigNumberish,
    expectedEndVTokenBalance: BigNumberish,
    expectedEndVQuoteBalance: BigNumberish,
    checkApproximateVTokenBalance: Boolean,
    expectedSumALast?: BigNumberish,
    expectedSumBLast?: BigNumberish,
    expectedSumFpLast?: BigNumberish,
    expectedSumFeeLast?: BigNumberish,
  ) {
    await updateRangeOrder(
      user,
      userAccountNo,
      tokenAddress,
      tickLower,
      tickUpper,
      liquidityDelta,
      closeTokenPosition,
      limitOrderType,
    );
    checkApproximateVTokenBalance
      ? await checkVTokenBalanceApproxiate(userAccountNo, tokenAddress, expectedEndVTokenBalance, 8)
      : await checkVTokenBalance(userAccountNo, tokenAddress, expectedEndVTokenBalance);
    await checkVQuoteBalance(userAccountNo, expectedEndVQuoteBalance);
    await checkLiquidityPositionNum(userAccountNo, tokenAddress, expectedEndLiquidityPositionNum);
    if (liquidityPositionNum !== -1) {
      await checkLiquidityPositionDetails(
        userAccountNo,
        tokenAddress,
        liquidityPositionNum,
        tickLower,
        tickUpper,
        limitOrderType,
        liquidityDelta,
        expectedSumALast,
        expectedSumBLast,
        expectedSumFpLast,
        expectedSumFeeLast,
      );
    }
  }

  async function checkGlobalParams(
    expectedSumB?: BigNumberish,
    expectedSumA?: BigNumberish,
    expectedSumFp?: BigNumberish,
    expectedSumFee?: BigNumberish,
  ) {
    const fpGlobal = await vPoolWrapper.fpGlobal();
    const sumFeeX128 = await vPoolWrapper.sumFeeGlobalX128();
    //Already a multiple of e6 since token(e18) and liquidity(e12)
    if (typeof expectedSumB !== 'undefined') {
      const sumB = X128ToDecimal(fpGlobal.sumBX128, 10n);
      expect(sumB).to.eq(expectedSumB);
    }
    //Already a multiple of e-12 since token price has that multiple
    if (typeof expectedSumA !== 'undefined') {
      const sumA = X128ToDecimal(fpGlobal.sumAX128, 20n);
      expect(sumA).to.eq(expectedSumA);
    }
    //Already a multiple of e-6 since Fp = a*sumB
    if (typeof expectedSumFp !== 'undefined') {
      const sumFp = X128ToDecimal(fpGlobal.sumFpX128, 19n);
      expect(sumFp).to.eq(expectedSumFp);
    }

    if (typeof expectedSumFee !== 'undefined') {
      const sumFee = X128ToDecimal(sumFeeX128, 16n);
      expect(sumFee).to.eq(expectedSumFee);
    }
  }

  async function checkTickParams(
    tickIndex: BigNumberish,
    expectedSumB?: BigNumberish,
    expectedSumA?: BigNumberish,
    expectedSumFp?: BigNumberish,
    expectedSumFee?: BigNumberish,
  ) {
    const tick = await vPoolWrapper.ticksExtended(tickIndex);
    //Already a multiple of e6 since token(e18) and liquidity(e12)
    if (typeof expectedSumB !== 'undefined') {
      const sumB = X128ToDecimal(tick.sumBOutsideX128, 10n);
      expect(sumB).to.eq(expectedSumB);
    }
    //Already a multiple of e-12 since token price has that multiple
    if (typeof expectedSumA !== 'undefined') {
      const sumA = X128ToDecimal(tick.sumALastX128, 20n);
      expect(sumA).to.eq(expectedSumA);
    }
    //Already a multiple of e-6 since Fp = a*sumB
    if (typeof expectedSumFp !== 'undefined') {
      const sumFp = X128ToDecimal(tick.sumFpOutsideX128, 19n);
      expect(sumFp).to.eq(expectedSumFp);
    }

    if (typeof expectedSumFee !== 'undefined') {
      const sumFee = X128ToDecimal(tick.sumFeeOutsideX128, 16n);
      expect(sumFee).to.eq(expectedSumFee);
    }
  }

  async function initializePool(
    rageTradeFactory: RageTradeFactory,
    initialMarginRatioBps: BigNumberish,
    maintainanceMarginRatioBps: BigNumberish,
    twapDuration: BigNumberish,
    initialPrice: BigNumberish,
    lpFee: BigNumberish,
    protocolFee: BigNumberish,
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    await await oracle.setSqrtPriceX96(initialPrice);

    await rageTradeFactory.initializePool({
      deployVTokenParams: {
        vTokenName: 'vWETH',
        vTokenSymbol: 'vWETH',
        cTokenDecimals: 18,
      },
      poolInitialSettings: {
        initialMarginRatioBps,
        maintainanceMarginRatioBps,
        maxVirtualPriceDeviationRatioBps: 10000,
        twapDuration,
        isAllowedForTrade: false,
        isCrossMargined: false,
        oracle: oracle.address,
      },
      liquidityFeePips: lpFee,
      protocolFeePips: protocolFee,
      slotsToInitialize: 100,
    });

    const eventFilter = rageTradeFactory.filters.PoolInitialized();
    const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    return { vTokenAddress, realToken, oracle, vPool, vPoolWrapper };
  }

  async function getPoolSettings(vTokenAddress: string) {
    let {
      settings: {
        initialMarginRatioBps,
        maintainanceMarginRatioBps,
        maxVirtualPriceDeviationRatioBps,
        twapDuration,
        isAllowedForTrade,
        isCrossMargined,
        oracle,
      },
    } = await clearingHouseTest.getPoolInfo(truncate(vTokenAddress));
    return {
      initialMarginRatioBps,
      maintainanceMarginRatioBps,
      maxVirtualPriceDeviationRatioBps,
      twapDuration,
      isAllowedForTrade,
      isCrossMargined,
      oracle,
    };
  }

  before(async () => {
    await activateMainnetFork();

    settlementToken = await hre.ethers.getContractAt('IERC20', SETTLEMENT_TOKEN);

    dummyTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(148392483294).toHexString(), 20);

    const vQuoteFactory = await hre.ethers.getContractFactory('VQuote');
    // vQuote = await vQuoteFactory.deploy(SETTLEMENT_TOKEN);
    // vQuoteAddress = vQuote.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user0 = signers[1];
    user1 = signers[2];
    user2 = signers[3];

    const initialMargin = 2000;
    const maintainanceMargin = 1000;
    const timeHorizon = 300;
    const initialPrice = tickToSqrtPriceX96(-199590);
    const lpFee = 1000;
    const protocolFee = 500;

    const futureVPoolFactoryAddress = await getCreateAddressFor(admin, 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(admin, 4);

    // const VPoolWrapperDeployer = await (
    //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    // ).deploy(futureVPoolFactoryAddress);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const clearingHouseTestLogic = await (
      await hre.ethers.getContractFactory('ClearingHouseTest', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy();

    const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapperMockRealistic')).deploy();

    const insuranceFundLogic = await (await hre.ethers.getContractFactory('InsuranceFund')).deploy();

    const nativeOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    const rageTradeFactory = await (
      await hre.ethers.getContractFactory('RageTradeFactory')
    ).deploy(
      clearingHouseTestLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      settlementToken.address,
    );

    vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());
    vQuoteAddress = vQuote.address;

    clearingHouseTest = await hre.ethers.getContractAt('ClearingHouseTest', await rageTradeFactory.clearingHouse());

    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouseTest.insuranceFund());

    // await vQuote.transferOwnership(VPoolFactory.address);
    // const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    // realToken = await realTokenFactory.deploy();

    let out = await initializePool(
      rageTradeFactory,
      initialMargin,
      maintainanceMargin,
      timeHorizon,
      initialPrice,
      lpFee,
      protocolFee,
    );

    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;
    vPool = (await hre.ethers.getContractAt(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      out.vPool,
    )) as IUniswapV3Pool;
    vToken = await hre.ethers.getContractAt('VToken', vTokenAddress);

    const vPoolWrapperAddress = out.vPoolWrapper;
    // constants = await VPoolFactory.constants();

    // const vPoolWrapperDeployerMock = await (
    //   await hre.ethers.getContractFactory('VPoolWrapperDeployerMockRealistic')
    // ).deploy(ADDRESS_ZERO);
    // const vPoolWrapperMockAddress = await vPoolWrapperDeployerMock.callStatic.deployVPoolWrapper(
    //   vTokenAddress,
    //   vPool.address,
    //   oracle.address,
    //   lpFee,
    //   protocolFee,
    //   initialMargin,
    //   maintainanceMargin,
    //   timeHorizon,
    //   false,
    // );
    // await vPoolWrapperDeployerMock.deployVPoolWrapper(
    //   vTokenAddress,
    //   vPool.address,
    //   oracle.address,
    //   lpFee,
    //   protocolFee,
    //   initialMargin,
    //   maintainanceMargin,
    //   timeHorizon,
    //   false,
    // );

    // const mockBytecode = await hre.ethers.provider.getCode(vPoolWrapperMockAddress);

    // await network.provider.send('hardhat_setCode', [vPoolWrapperAddress, mockBytecode]);

    vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapperMockRealistic', vPoolWrapperAddress);

    // increases cardinality for twap
    await vPool.increaseObservationCardinalityNext(100);

    const block = await hre.ethers.provider.getBlock('latest');
    initialBlockTimestamp = block.timestamp;
    settlementTokenOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
    await clearingHouseTest.updateCollateralSettings(settlementToken.address, {
      oracle: settlementTokenOracle.address,
      twapDuration: 300,
      isAllowedForDeposit: true,
    });
  });

  after(deactivateMainnetFork);

  describe('#Init Params', () => {
    it('Set Params', async () => {
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

      const removeLimitOrderFee = parseTokenAmount(10, 6);
      const minimumOrderNotional = parseTokenAmount(1, 6).div(100);
      const minRequiredMargin = parseTokenAmount(20, 6);

      await clearingHouseTest.updateProtocolSettings(
        liquidationParams,
        removeLimitOrderFee,
        minimumOrderNotional,
        minRequiredMargin,
      );

      const protocol = await clearingHouseTest.getProtocolInfo();
      const curPaused = await clearingHouseTest.paused();

      await vPoolWrapper.setFpGlobalLastTimestamp(0);

      expect(protocol.minRequiredMargin).eq(minRequiredMargin);
      expect(protocol.liquidationParams.rangeLiquidationFeeFraction).eq(liquidationParams.rangeLiquidationFeeFraction);
      expect(protocol.liquidationParams.tokenLiquidationFeeFraction).eq(liquidationParams.tokenLiquidationFeeFraction);
      expect(protocol.liquidationParams.insuranceFundFeeShareBps).eq(liquidationParams.insuranceFundFeeShareBps);

      expect(protocol.removeLimitOrderFee).eq(removeLimitOrderFee);
      expect(protocol.minimumOrderNotional).eq(minimumOrderNotional);
      expect(curPaused).to.be.false;
    });
  });

  describe('#Initialize', () => {
    it('Steal Funds', async () => {
      await stealFunds(SETTLEMENT_TOKEN, 6, user0.address, '1000000', whaleFosettlementToken);
      await stealFunds(SETTLEMENT_TOKEN, 6, user1.address, '1000000', whaleFosettlementToken);
      await stealFunds(SETTLEMENT_TOKEN, 6, user2.address, '1000000', whaleFosettlementToken);

      expect(await settlementToken.balanceOf(user0.address)).to.eq(parseTokenAmount('1000000', 6));
      expect(await settlementToken.balanceOf(user1.address)).to.eq(parseTokenAmount('1000000', 6));
      expect(await settlementToken.balanceOf(user2.address)).to.eq(parseTokenAmount('1000000', 6));
    });
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user0).createAccount();
      user0AccountNo = 0;
      expect(await clearingHouseTest.numAccounts()).to.eq(1);
      expect(await clearingHouseTest.getAccountOwner(user0AccountNo)).to.eq(user0.address);
      // expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user0AccountNo)).to.eq(user0AccountNo);
    });
    it('Create Account - 2', async () => {
      await clearingHouseTest.connect(user1).createAccount();
      user1AccountNo = 1;
      expect(await clearingHouseTest.numAccounts()).to.eq(2);
      expect(await clearingHouseTest.getAccountOwner(user1AccountNo)).to.eq(user1.address);
      // expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user1AccountNo)).to.eq(user1AccountNo);
    });
    it('Create Account - 3', async () => {
      await clearingHouseTest.connect(user2).createAccount();
      user2AccountNo = 2;
      expect(await clearingHouseTest.numAccounts()).to.eq(3);
      expect(await clearingHouseTest.getAccountOwner(user2AccountNo)).to.eq(user2.address);
      // expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user2AccountNo)).to.eq(user2AccountNo);
    });
    it('Tokens Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokens(vTokenAddress)).to.eq(vTokenAddress);
    });

    it('Add Token Position Support - Pass', async () => {
      const settings = await getPoolSettings(vTokenAddress);
      settings.isAllowedForTrade = true;
      await clearingHouseTest.connect(admin).updatePoolSettings(truncate(vTokenAddress), settings);
      expect((await clearingHouseTest.getPoolInfo(truncate(vTokenAddress))).settings.isAllowedForTrade).to.be.true;
    });
    it('AddVQuote Deposit Support  - Pass', async () => {
      // await clearingHouseTest.connect(admin).updateSupportedDeposits(settlementToken.address, true);
      expect(
        (await clearingHouseTest.getCollateralInfo(truncate(settlementToken.address))).settings.isAllowedForDeposit,
      ).to.be.true;
    });
  });

  describe('#Scenario', async () => {
    it('Timestamp And Oracle Update - 0', async () => {
      await vPoolWrapper.setBlockTimestamp(0);
      const realSqrtPrice = await priceToSqrtPriceX96(2150.63617866738, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(0);
    });
    it('Acct[0] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user0, user0AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
      await checkSettlementVTokenBalance(user0.address, parseTokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkSettlementVTokenBalance(clearingHouseTest.address, parseTokenAmount(10n ** 5n, 6));
      await checkDepositBalance(user0AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
    });
    it('Acct[0] Adds Liq b/w ticks (-200820 to -199360) @ tickCurrent = -199590', async () => {
      const tickLower = -200820;
      const tickUpper = -199360;
      const liquidityDelta = 75407230733517400n;
      const limitOrderType = 0;
      const expectedVTokenBalance = -18595999999997900000n;
      const expectedVQuoteBalance = '-208523902880';

      const expectedSumALast = 0n;
      const expectedSumBLast = 0n;
      const expectedSumFpLast = 0n;
      const expectedSumFeeLast = 0n;

      await updateRangeOrderAndCheck(
        user0,
        user0AccountNo,
        vTokenAddress,
        vQuoteAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        0,
        1,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        true,
        expectedSumALast,
        expectedSumBLast,
        expectedSumFpLast,
        expectedSumFeeLast,
      );
    });

    it('Timestamp and Oracle Update - 600', async () => {
      const timestampIncrease = 600;
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2150.63617866738, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });
    it('Acct[2] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user2, user2AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
      await checkSettlementVTokenBalance(user2.address, parseTokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkSettlementVTokenBalance(clearingHouseTest.address, parseTokenAmount(2n * 10n ** 5n, 6));
      await checkDepositBalance(user2AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
    });
    it('Acct[2] Short ETH : Price Changes (StartTick = -199590, EndTick = -199700)', async () => {
      const startTick = -199590;
      const endTick = -199700;

      const swapTokenAmount = '-8969616182683600000';
      const expectedVTokenBalance = '-8969616182683600000';

      //TODO: Check
      const expectedVQuoteBalance = 19146228583n - 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 19146228583n - 1n;
      const expectedFundingPayment = 0n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );
    });
    it('Acct[1] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user1, user1AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
      await checkSettlementVTokenBalance(user1.address, parseTokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkSettlementVTokenBalance(clearingHouseTest.address, parseTokenAmount(3n * 10n ** 5n, 6));
      await checkDepositBalance(user1AccountNo, settlementToken.address, parseTokenAmount(10n ** 5n, 6));
    });
    it('Timestamp and Oracle Update - 1200', async () => {
      const timestampIncrease = 1200;
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2127.10998824933, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });
    it('Acct[1] Adds Liq b/w ticks (-200310 to -199820) @ tickCurrent = -199700', async () => {
      const tickLower = -200310;
      const tickUpper = -199820;
      const liquidityDelta = 22538439850760800n;
      const limitOrderType = 0;
      const expectedEndVTokenBalance = 0;
      const expectedEndVQuoteBalance = -25000000000n;

      const expectedSumALast = 0n;
      const expectedSumBLast = 0n;
      const expectedSumFpLast = 0n;
      const expectedSumFeeLast = 0n;

      const expectedTick199820SumB = 1189490198145n;
      const expectedTick199820SumA = 1484140n;
      const expectedTick199820SumFp = 8778310n;
      const expectedTick199820SumFee = 2542858n;

      const expectedTick200310SumB = 1189490198145n;
      const expectedTick200310SumA = 1484140n;
      const expectedTick200310SumFp = 8778310n;
      const expectedTick200310SumFee = 2542858n;

      await updateRangeOrderAndCheck(
        user1,
        user1AccountNo,
        vTokenAddress,
        vQuoteAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        0,
        1,
        expectedEndVTokenBalance,
        expectedEndVQuoteBalance,
        false,
        expectedSumALast,
        expectedSumBLast,
        expectedSumFpLast,
        expectedSumFeeLast,
      );
      await checkTickParams(
        -199820,
        expectedTick199820SumB,
        expectedTick199820SumA,
        expectedTick199820SumFp,
        expectedTick199820SumFee,
      );
      await checkTickParams(
        -200310,
        expectedTick200310SumB,
        expectedTick200310SumA,
        expectedTick200310SumFp,
        expectedTick200310SumFee,
      );
    });

    it('Timestamp and Oracle Update - 1900', async () => {
      const timestampIncrease = 1900;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2127.10998824933, vQuote, vToken);
      await await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199700, EndTick = -199820)', async () => {
      const startTick = -199700;
      const endTick = -199820;

      const swapTokenAmount = '-9841461389446900000';
      const expectedVTokenBalance = '-18811077572130500000';
      const expectedVQuoteBalance = 39913423321n - 1n;

      // const expectedSumB = ((2494598646n*(1n<<128n))/(10n**13n))+1n;
      const expectedSumB = 2494598646462n;
      const expectedSumA = 2345128n;
      const expectedSumFp = 19019671n;
      const expectedSumFee = 5300982n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 1484140n;
      const expectedTickSumFp = 8778310n;
      const expectedTickSumFee = 2542858n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 20767051316n;
      const expectedFundingPayment = 143421n + 1n;

      const expectedAccount1UnrealizedFunding = 0n;
      const expectedAccount1UnrealizedFee = 0n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 2600', async () => {
      const timestampIncrease = 2600;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2101.73847049388, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050', async () => {
      const startTick = -199820;
      const endTick = -200050;

      const swapTokenAmount = '-24716106801005000000';
      const expectedVTokenBalance = '-43527184373135500000';

      //TODO: Check
      const expectedVQuoteBalance = 91163779610n - 1n;

      const expectedSumB = 5018049315957n + 1n;
      const expectedSumA = 3195846n;
      const expectedSumFp = 40241668n;
      const expectedSumFee = 10541355n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 51250196260n;
      const expectedFundingPayment = 160028n + 1n;

      const expectedTickSumB = 1305108448316n + 3n;
      const expectedTickSumA = 3195846n;
      const expectedTickSumFp = 11102790n;
      const expectedTickSumFee = 2758123n + 1n;

      const expectedAccount1UnrealizedFunding = 0n;
      const expectedAccount1UnrealizedFee = 11810983n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 3300', async () => {
      const timestampIncrease = 3300;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2053.95251980329, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Long  ETH : Price Changes (StartTick = -200050, EndTick = -199820', async () => {
      const startTick = -200050;
      const endTick = -199820;

      const swapTokenAmount = '24716106801005000000';
      const expectedVTokenBalance = '-18811077572130500000';

      const expectedVQuoteBalance = 39759963661n - 3n;

      const expectedSumB = 2494598646462n;
      const expectedSumA = 4027221n;
      const expectedSumFp = 81960507n;
      const expectedSumFee = 15781728n + 1n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 4027221n;
      const expectedTickSumFp = 60007362n + 1n;
      const expectedTickSumFee = 13023604n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = -51404177823n - 2n;
      const expectedFundingPayment = 361873n + 1n;

      const expectedAccount1UnrealizedFunding = -47285n + 1n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 4100', async () => {
      const timestampIncrease = 4100;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2101.73847049388, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Long  ETH : Price Changes (StartTick = -199820, EndTick = -199540', async () => {
      const startTick = -199820;
      //TODO: Check
      const endTick = -199540 - 1;

      const swapTokenAmount = '22871896768962800000';
      const expectedVTokenBalance = '4060819196832300000';

      const expectedVQuoteBalance = -9037007285n - 4n;

      const expectedSumB = -538518542231n;
      const expectedSumA = 4999470n;
      const expectedSumFp = 106214217n + 1n;
      const expectedSumFee = 22243187n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = -48797153836n - 1n;
      const expectedFundingPayment = 182889n + 1n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 4027221n;
      const expectedTickSumFp = 60007362n + 1n;
      const expectedTickSumFee = 13023604n + 1n;

      const expectedAccount1UnrealizedFunding = -47285n + 1n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 4500', async () => {
      const timestampIncrease = 4500;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2161.41574705594, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199540, EndTick = -199820', async () => {
      const startTick = -199540 - 1;
      const endTick = -199820;

      const swapTokenAmount = '-22871896768962800000';
      const expectedVTokenBalance = '-18811077572130500000';

      const expectedVQuoteBalance = 39613949988n - 4n;

      const expectedSumB = 2494598646462n;
      const expectedSumA = 5599294n;
      const expectedSumFp = 102984058n + 1n;
      const expectedSumFee = 28704645n + 1n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 4027221n;
      const expectedTickSumFp = 60007362n + 1n;
      const expectedTickSumFee = 13023604n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 48650981631n - 1n;
      const expectedFundingPayment = -24358n + 1n;

      const expectedAccount1UnrealizedFunding = -47285n + 1n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 4600', async () => {
      const timestampIncrease = 4600;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2141.33749022076, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050', async () => {
      const startTick = -199820;
      const endTick = -200050;

      const swapTokenAmount = '-24716106801005000000';
      //TODO: Correction in finquant test cases
      const expectedVTokenBalance = '-43527184373135500000';

      const expectedVQuoteBalance = 90864172645n - 4n;

      const expectedSumB = 5018049315957n + 1n;
      const expectedSumA = 5739622n;
      const expectedSumFp = 106484699n + 1n;
      const expectedSumFee = 33945018n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 51250196260n;
      const expectedFundingPayment = 26396n + 1n;

      const expectedTickSumB = 1305108448316n + 3n;
      const expectedTickSumA = 5739622n;
      const expectedTickSumFp = 26108494n;
      const expectedTickSumFee = 15681040n + 1n;

      const expectedAccount1UnrealizedFunding = -47285n + 1n;
      const expectedAccount1UnrealizedFee = 35432951n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-199820, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 5300', async () => {
      const timestampIncrease = 5300;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2053.95251980329, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200050, EndTick = -200310', async () => {
      const startTick = -200050;
      const endTick = -200310;

      const swapTokenAmount = '-28284342105582900000';
      const expectedVTokenBalance = '-71811526478718400000';
      const expectedVQuoteBalance = 148094287097n - 4n;

      const expectedSumB = 7905807594282n + 1n;
      const expectedSumA = 6570998n;
      const expectedSumFp = 148203538n + 1n;
      const expectedSumFee = 39796806n + 1n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 1484140n;
      const expectedTickSumFp = 8778310n;
      const expectedTickSumFee = 2542858n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 57229752578n;
      const expectedFundingPayment = 361873n + 1n;

      const expectedAccount1UnrealizedFunding = -94570n + 2n;
      const expectedAccount1UnrealizedFee = 48621967n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-200310, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 5800', async () => {
      const timestampIncrease = 5800;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2001.24061387234, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[1] Removes Liq b/w ticks (-200310 to -199820) @ tickCurrent = -200310', async () => {
      const tickLower = -200310;
      const tickUpper = -199820;
      const liquidityDelta = -22538439850760800n;
      const limitOrderType = 0;
      const expectedEndVTokenBalance = 12196020739034000000n;
      const expectedEndVQuoteBalance = -24951543167n + 1n;

      // const expectedSumALast = 6570998n;
      // const expectedSumBLast = -115618250170n;
      // const expectedSumFpLast = 32327135n;
      // const expectedSumFeeLast = 21572907n;

      const expectedAccount1UnrealizedFunding = -165134n;
      const expectedAccount1UnrealizedFee = 48621967n + 1n;

      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );

      await updateRangeOrderAndCheck(
        user1,
        user1AccountNo,
        vTokenAddress,
        vQuoteAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        -1,
        0,
        expectedEndVTokenBalance,
        expectedEndVQuoteBalance,
        true,
      );
    });

    it('Timestamp and Oracle Update - 6200', async () => {
      const timestampIncrease = 6200;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2001.24061387234, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200310, EndTick = -200460', async () => {
      const startTick = -200310;
      const endTick = -200460;

      const swapTokenAmount = '-12692319513534700000';
      const expectedVTokenBalance = '-84503845992253100000';
      const expectedVQuoteBalance = 173255240934n - 4n;

      const expectedSumB = 9588977681563n;
      const expectedSumA = 7612477n;
      const expectedSumFp = 230540892n + 1n;
      const expectedSumFee = 43138396n + 1n;

      const expectedTickSumB = 0n;
      const expectedTickSumA = 0n;
      const expectedTickSumFp = 0n;
      const expectedTickSumFee = 0n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 25160205935n;
      const expectedFundingPayment = 747901n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-200310, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
    });

    it('Timestamp and Oracle Update - 6300', async () => {
      const timestampIncrease = 6300;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1991.25998215442, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200460, EndTick = -200610', async () => {
      const startTick = -200460;
      const endTick = -200610;

      const swapTokenAmount = '-12787864980350100000';
      const expectedVTokenBalance = '-97291710972603200000';
      const expectedVQuoteBalance = 198227557862n - 4n;

      const expectedSumB = 11284818366330n;
      const expectedSumA = 7727632n;
      const expectedSumFp = 241583015n + 1n;
      const expectedSumFee = 46455018n + 2n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 24972219619n;
      const expectedFundingPayment = 97308n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });

    it('Timestamp and Oracle Update - 7200', async () => {
      const timestampIncrease = 7200;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1942.0979282388, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200610, EndTick = -200750', async () => {
      const startTick = -200610;
      const endTick = -200750;

      const swapTokenAmount = '-12022178314034100000';
      const expectedVTokenBalance = '-109313889286637300000';
      const expectedVQuoteBalance = 221367579949n - 4n;

      const expectedSumB = 12879118832888n + 1n;
      const expectedSumA = 8738332n;
      const expectedSumFp = 355638731n + 1n;
      const expectedSumFee = 49528172n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 23139038760n;
      const expectedFundingPayment = 983326n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });

    it('Timestamp and Oracle Update - 7600', async () => {
      const timestampIncrease = 7600;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      await vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1915.09933823398, vQuote, vToken);
      await oracle.setSqrtPriceX96(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200750, EndTick = -200800', async () => {
      const startTick = -200750;
      const endTick = -200800;

      const swapTokenAmount = '-4314069685093700000';
      const expectedVTokenBalance = '-113627958971731000000';
      const expectedVQuoteBalance = 229592833231n - 4n;

      const expectedSumB = 13451221752347n + 1n;
      const expectedSumA = 9181288n;
      const expectedSumFp = 412687502n + 2n;
      const expectedSumFee = 50620524n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedVQuoteAmountOutWithFee = 8224769071n;
      const expectedFundingPayment = 484210n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vQuoteAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedVTokenBalance,
        expectedVQuoteBalance,
        expectedTokenAmountOut,
        expectedVQuoteAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });
  });
});
