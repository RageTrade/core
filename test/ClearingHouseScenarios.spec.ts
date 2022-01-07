import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ContractReceipt, ContractTransaction, ethers, providers } from 'ethers';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
import {
  AccountTest,
  VPoolFactory,
  ClearingHouse,
  ERC20,
  RealTokenMock,
  OracleMock,
  IERC20,
  ClearingHouseTest,
  IUniswapV3Pool,
  VPoolWrapperMockRealistic,
  VToken,
  VBase,
  Account__factory,
} from '../typechain-types';

import { AccountInterface, TokenPositionChangeEvent } from '../typechain-types/Account';

import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import {
  UNISWAP_FACTORY_ADDRESS,
  DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './utils/realConstants';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { stealFunds, tokenAmount } from './utils/stealFunds';
import {
  sqrtPriceX96ToTick,
  priceToSqrtPriceX96WithoutContract,
  priceToTick,
  tickToPrice,
  tickToSqrtPriceX96,
  sqrtPriceX96ToPrice,
  priceToSqrtPriceX96,
  sqrtPriceX96ToPriceX128,
  priceX128ToPrice,
} from './utils/price-tick';

import { smock } from '@defi-wonderland/smock';
import { ADDRESS_ZERO, priceToClosestTick } from '@uniswap/v3-sdk';
import { FundingPaymentEvent } from '../typechain-types/Account';
const whaleForBase = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

config();
const { ALCHEMY_KEY } = process.env;

describe('Clearing House Library', () => {
  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let constants: ConstantsStruct;
  let clearingHouseTest: ClearingHouseTest;
  let vPool: IUniswapV3Pool;
  let vPoolWrapper: VPoolWrapperMockRealistic;
  let vToken: VToken;
  let vBase: VBase;

  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user0: SignerWithAddress;
  let user1: SignerWithAddress;
  let user0AccountNo: BigNumberish;
  let user1AccountNo: BigNumberish;
  let user2: SignerWithAddress;
  let user2AccountNo: BigNumberish;

  let rBase: IERC20;

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

  async function checkTokenBalance(accountNo: BigNumberish, vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
  }

  async function checkTokenBalanceApproxiate(
    accountNo: BigNumberish,
    vTokenAddress: string,
    vTokenBalance: BigNumberish,
    digitsToApproximate: BigNumberish,
  ) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.balance.sub(vTokenBalance).abs()).lt(BigNumber.from(10).pow(digitsToApproximate));
  }

  async function checkTraderPosition(accountNo: BigNumberish, vTokenAddress: string, traderPosition: BigNumberish) {
    const vTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(accountNo, vTokenAddress);
    expect(vTokenPosition.netTraderPosition).to.eq(traderPosition);
  }

  async function checkDepositBalance(accountNo: BigNumberish, vTokenAddress: string, vTokenBalance: BigNumberish) {
    const balance = await clearingHouseTest.getAccountDepositBalance(accountNo, vTokenAddress);
    expect(balance).to.eq(vTokenBalance);
  }

  async function checkRealBaseBalance(address: string, tokenAmount: BigNumberish) {
    expect(await rBase.balanceOf(address)).to.eq(tokenAmount);
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
    tokenAmount: BigNumberish,
  ) {
    await rBase.connect(user).approve(clearingHouseTest.address, tokenAmount);
    const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(tokenAddress);
    await clearingHouseTest.connect(user).addMargin(userAccountNo, truncatedVBaseAddress, tokenAmount);
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
    expectedBaseAmountOut: BigNumberish,
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
      .filter(event => event?.name === 'TokenPositionChange') as unknown as TokenPositionChangeEvent[];

    const event = eventList[0];
    expect(event.args.accountNo).to.eq(expectedUserAccountNo);
    expect(event.args.vTokenAddress).to.eq(expectedTokenAddress);
    expect(event.args.tokenAmountOut).to.eq(expectedTokenAmountOut);
    expect(event.args.baseAmountOut).to.eq(expectedBaseAmountOut);
  }

  async function checkFundingPaymentEvent(
    txnReceipt: ContractReceipt,
    expectedUserAccountNo: BigNumberish,
    expectedTokenAddress: string,
    expectedTickLower: BigNumberish,
    expectedTickUpper: BigNumberish,
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
      .filter(event => event?.name === 'FundingPayment') as unknown as FundingPaymentEvent[];

    const event = eventList[0];

    expect(event.args.accountNo).to.eq(expectedUserAccountNo);
    expect(event.args.vTokenAddress).to.eq(expectedTokenAddress);
    expect(event.args.tickLower).to.eq(expectedTickLower);
    expect(event.args.tickUpper).to.eq(expectedTickUpper);
    expect(event.args.amount).to.eq(expectedFundingPayment);
  }

  async function checkSwapEvents(
    swapTxn: ContractTransaction,
    expectedUserAccountNo: BigNumberish,
    expectedTokenAddress: string,
    expectedTokenAmountOut: BigNumberish,
    expectedBaseAmountOutWithFee: BigNumberish,
    expectedFundingPayment: BigNumberish,
  ) {
    const swapReceipt = await swapTxn.wait();

    await checkTokenPositionChangeEvent(
      swapReceipt,
      expectedUserAccountNo,
      expectedTokenAddress,
      expectedTokenAmountOut,
      expectedBaseAmountOutWithFee,
    );
    await checkFundingPaymentEvent(
      swapReceipt,
      expectedUserAccountNo,
      expectedTokenAddress,
      0,
      0,
      expectedFundingPayment,
    );
  }

  async function swapTokenAndCheck(
    user: SignerWithAddress,
    userAccountNo: BigNumberish,
    tokenAddress: string,
    baseAddress: string,
    amount: BigNumberish,
    sqrtPriceLimit: BigNumberish,
    isNotional: boolean,
    isPartialAllowed: boolean,
    expectedStartTick: number,
    expectedEndTick: number,
    expectedEndTokenBalance: BigNumberish,
    expectedEndBaseBalance: BigNumberish,
    expectedTokenAmountOut: BigNumberish,
    expectedBaseAmountOutWithFee: BigNumberish,
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
    await checkTokenBalance(user2AccountNo, tokenAddress, expectedEndTokenBalance);
    await checkTokenBalance(user2AccountNo, baseAddress, expectedEndBaseBalance);
    await checkSwapEvents(
      swapTxn,
      userAccountNo,
      tokenAddress,
      expectedTokenAmountOut,
      expectedBaseAmountOutWithFee,
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
    baseAddress: string,
    tickLower: BigNumberish,
    tickUpper: BigNumberish,
    liquidityDelta: BigNumberish,
    closeTokenPosition: boolean,
    limitOrderType: number,
    liquidityPositionNum: BigNumberish,
    expectedEndLiquidityPositionNum: BigNumberish,
    expectedEndTokenBalance: BigNumberish,
    expectedEndBaseBalance: BigNumberish,
    checkApproximateTokenBalance: Boolean,
    expectedSumALast: BigNumberish,
    expectedSumBLast: BigNumberish,
    expectedSumFpLast: BigNumberish,
    expectedSumFeeLast: BigNumberish,
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
    checkApproximateTokenBalance
      ? await checkTokenBalanceApproxiate(userAccountNo, tokenAddress, expectedEndTokenBalance, 8)
      : await checkTokenBalance(userAccountNo, tokenAddress, expectedEndTokenBalance);
    await checkTokenBalance(userAccountNo, baseAddress, expectedEndBaseBalance);
    await checkLiquidityPositionNum(userAccountNo, tokenAddress, expectedEndLiquidityPositionNum);
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
    VPoolFactory: VPoolFactory,
    initialMarginRatio: BigNumberish,
    maintainanceMarginRatio: BigNumberish,
    twapDuration: BigNumberish,
    initialPrice: BigNumberish,
    lpFee: BigNumberish,
    protocolFee: BigNumberish,
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    oracle.setSqrtPrice(initialPrice);

    await VPoolFactory.initializePool(
      {
        setupVTokenParams: {
          vTokenName: 'vWETH',
          vTokenSymbol: 'vWETH',
          realTokenAddress: realToken.address,
          oracleAddress: oracle.address,
        },
        extendedLpFee: lpFee,
        protocolFee: protocolFee,
        initialMarginRatio,
        maintainanceMarginRatio,
        twapDuration,
        whitelisted: false,
      },
      0,
    );

    const eventFilter = VPoolFactory.filters.PoolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    return { vTokenAddress, realToken, oracle, vPool, vPoolWrapper };
  }

  before(async () => {
    await activateMainnetFork();

    dummyTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(148392483294).toHexString(), 20);

    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    vBase = await vBaseFactory.deploy(REAL_BASE);
    vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user0 = signers[1];
    user1 = signers[2];
    user2 = signers[3];

    const initialMargin = 20_000;
    const maintainanceMargin = 10_000;
    const timeHorizon = 300;
    const initialPrice = tickToSqrtPriceX96(-199590);
    const lpFee = 1000;
    const protocolFee = 500;

    const futureVPoolFactoryAddress = await getCreateAddressFor(admin, 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(admin, 4);

    const VPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    clearingHouseTest = await (
      await hre.ethers.getContractFactory('ClearingHouseTest', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy(futureVPoolFactoryAddress, REAL_BASE, futureInsurnaceFundAddress);

    const VPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      vBaseAddress,
      clearingHouseTest.address,
      VPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      UNISWAP_V3_POOL_BYTE_CODE_HASH,
    );

    const InsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(REAL_BASE, clearingHouseTest.address);

    await vBase.transferOwnership(VPoolFactory.address);
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    realToken = await realTokenFactory.deploy();

    let out = await initializePool(
      VPoolFactory,
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
    constants = await VPoolFactory.constants();

    const vPoolWrapperDeployerMock = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployerMockRealistic')
    ).deploy(ADDRESS_ZERO);
    const vPoolWrapperMockAddress = await vPoolWrapperDeployerMock.callStatic.deployVPoolWrapper(
      vTokenAddress,
      vPool.address,
      oracle.address,
      lpFee,
      protocolFee,
      initialMargin,
      maintainanceMargin,
      timeHorizon,
      false,
      constants,
    );
    await vPoolWrapperDeployerMock.deployVPoolWrapper(
      vTokenAddress,
      vPool.address,
      oracle.address,
      lpFee,
      protocolFee,
      initialMargin,
      maintainanceMargin,
      timeHorizon,
      false,
      constants,
    );

    const mockBytecode = await hre.ethers.provider.getCode(vPoolWrapperMockAddress);

    await network.provider.send('hardhat_setCode', [vPoolWrapperAddress, mockBytecode]);

    vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapperMockRealistic', vPoolWrapperAddress);

    // increases cardinality for twap
    await vPool.increaseObservationCardinalityNext(100);

    const block = await hre.ethers.provider.getBlock('latest');
    initialBlockTimestamp = block.timestamp;

    rBase = await hre.ethers.getContractAt('IERC20', REAL_BASE);
  });

  after(deactivateMainnetFork);

  describe('#Init Params', () => {
    it('Set Params', async () => {
      const liquidationParams = {
        fixFee: tokenAmount(10, 6),
        minRequiredMargin: tokenAmount(20, 6),
        liquidationFeeFraction: 1500,
        tokenLiquidationPriceDeltaBps: 3000,
        insuranceFundFeeShareBps: 5000,
      };
      const removeLimitOrderFee = tokenAmount(10, 6);
      const minOrderNotional = tokenAmount(1, 6).div(100);

      await clearingHouseTest.setPlatformParameters(liquidationParams, removeLimitOrderFee, minOrderNotional);
      const curLiquidationParams = await clearingHouseTest.liquidationParams();
      const curRemoveLimitOrderFee = await clearingHouseTest.removeLimitOrderFee();
      const curMinOrderNotional = await clearingHouseTest.minimumOrderNotional();
      const curPaused = await clearingHouseTest.paused();

      await vPoolWrapper.setFpGlobalLastTimestamp(0);

      expect(liquidationParams.fixFee).eq(curLiquidationParams.fixFee);
      expect(liquidationParams.minRequiredMargin).eq(curLiquidationParams.minRequiredMargin);
      expect(liquidationParams.liquidationFeeFraction).eq(curLiquidationParams.liquidationFeeFraction);
      expect(liquidationParams.tokenLiquidationPriceDeltaBps).eq(curLiquidationParams.tokenLiquidationPriceDeltaBps);
      expect(liquidationParams.insuranceFundFeeShareBps).eq(curLiquidationParams.insuranceFundFeeShareBps);

      expect(removeLimitOrderFee).eq(curRemoveLimitOrderFee);
      expect(minOrderNotional).eq(curMinOrderNotional);
      expect(curPaused).to.be.false;
    });
  });

  describe('#Initialize', () => {
    it('Steal Funds', async () => {
      await stealFunds(REAL_BASE, 6, user0.address, '1000000', whaleForBase);
      await stealFunds(REAL_BASE, 6, user1.address, '1000000', whaleForBase);
      await stealFunds(REAL_BASE, 6, user2.address, '1000000', whaleForBase);

      expect(await rBase.balanceOf(user0.address)).to.eq(tokenAmount('1000000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('1000000', 6));
      expect(await rBase.balanceOf(user2.address)).to.eq(tokenAmount('1000000', 6));
    });
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user0).createAccount();
      user0AccountNo = 0;
      expect(await clearingHouseTest.numAccounts()).to.eq(1);
      expect(await clearingHouseTest.getAccountOwner(user0AccountNo)).to.eq(user0.address);
      expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user0AccountNo)).to.eq(user0AccountNo);
    });
    it('Create Account - 2', async () => {
      await clearingHouseTest.connect(user1).createAccount();
      user1AccountNo = 1;
      expect(await clearingHouseTest.numAccounts()).to.eq(2);
      expect(await clearingHouseTest.getAccountOwner(user1AccountNo)).to.eq(user1.address);
      expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user1AccountNo)).to.eq(user1AccountNo);
    });
    it('Create Account - 3', async () => {
      await clearingHouseTest.connect(user2).createAccount();
      user2AccountNo = 2;
      expect(await clearingHouseTest.numAccounts()).to.eq(3);
      expect(await clearingHouseTest.getAccountOwner(user2AccountNo)).to.eq(user2.address);
      expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user2AccountNo)).to.eq(user2AccountNo);
    });
    it('Tokens Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokenAddresses(vTokenAddress)).to.eq(vTokenAddress);
      expect(await clearingHouseTest.getTokenAddressInVTokenAddresses(vBaseAddress)).to.eq(vBaseAddress);
    });

    it('Add Token Position Support - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedVTokens(vTokenAddress, true);
      expect(await clearingHouseTest.supportedVTokens(vTokenAddress)).to.be.true;
    });
    it('Add Base Deposit Support  - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedDeposits(vBaseAddress, true);
      expect(await clearingHouseTest.supportedDeposits(vBaseAddress)).to.be.true;
    });
  });

  describe('#Scenario 1', async () => {
    it('Timestamp And Oracle Update - 0', async () => {
      vPoolWrapper.setBlockTimestamp(0);
      const realSqrtPrice = await priceToSqrtPriceX96(2150.63617866738, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(0);
    });
    it('Acct[0] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user0, user0AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
      await checkRealBaseBalance(user0.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkRealBaseBalance(clearingHouseTest.address, tokenAmount(10n ** 5n, 6));
      await checkDepositBalance(user0AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
    });
    it('Acct[0] Adds Liq b/w ticks (-200820 to -199360) @ tickCurrent = -199590', async () => {
      const tickLower = -200820;
      const tickUpper = -199360;
      const liquidityDelta = 75407230733517400n;
      const limitOrderType = 0;
      const expectedTokenBalance = -18595999999997900000n;
      const expectedBaseBalance = '-208523902880';

      const expectedSumALast = 0n;
      const expectedSumBLast = 0n;
      const expectedSumFpLast = 0n;
      const expectedSumFeeLast = 0n;

      await updateRangeOrderAndCheck(
        user0,
        user0AccountNo,
        vTokenAddress,
        vBaseAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        0,
        1,
        expectedTokenBalance,
        expectedBaseBalance,
        true,
        expectedSumALast,
        expectedSumBLast,
        expectedSumFpLast,
        expectedSumFeeLast,
      );
    });

    it('Timestamp and Oracle Update - 600', async () => {
      const timestampIncrease = 600;
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2150.63617866738, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });
    it('Acct[2] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user2, user2AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
      await checkRealBaseBalance(user2.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkRealBaseBalance(clearingHouseTest.address, tokenAmount(2n * 10n ** 5n, 6));
      await checkDepositBalance(user2AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
    });
    it('Acct[2] Short ETH : Price Changes (StartTick = -199590, EndTick = -199700)', async () => {
      const startTick = -199590;
      const endTick = -199700;

      const swapTokenAmount = '-8969616182683600000';
      const expectedTokenBalance = '-8969616182683600000';

      //TODO: Check
      const expectedBaseBalance = 19146228583n - 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 19146228583n - 1n;
      const expectedFundingPayment = 0n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
        expectedFundingPayment,
      );
    });
    it('Acct[1] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user1, user1AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
      await checkRealBaseBalance(user1.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkRealBaseBalance(clearingHouseTest.address, tokenAmount(3n * 10n ** 5n, 6));
      await checkDepositBalance(user1AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
    });
    it('Timestamp and Oracle Update - 1200', async () => {
      const timestampIncrease = 1200;
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2127.10998824933, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });
    it('Acct[1] Adds Liq b/w ticks (-200310 to -199820) @ tickCurrent = -199700', async () => {
      const tickLower = -200310;
      const tickUpper = -199820;
      const liquidityDelta = 22538439850760800n;
      const limitOrderType = 0;
      const expectedEndTokenBalance = 0;
      const expectedEndBaseBalance = -25000000000n;

      const expectedSumALast = 0n;
      const expectedSumBLast = 0n;
      const expectedSumFpLast = 0n;
      const expectedSumFeeLast = 0n;

      const expectedTick199820SumB = 1189490198145n;
      const expectedTick199820SumA = 746151n;
      const expectedTick199820SumFp = 0n;
      const expectedTick199820SumFee = 2542858n;

      const expectedTick200310SumB = 1189490198145n;
      const expectedTick200310SumA = 746151n;
      const expectedTick200310SumFp = 0n;
      const expectedTick200310SumFee = 2542858n;

      await updateRangeOrderAndCheck(
        user1,
        user1AccountNo,
        vTokenAddress,
        vBaseAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        0,
        1,
        expectedEndTokenBalance,
        expectedEndBaseBalance,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2127.10998824933, vBase, vToken);
      await oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199700, EndTick = -199820)', async () => {
      const startTick = -199700;
      const endTick = -199820;

      const swapTokenAmount = '-9841461389446900000';
      const expectedTokenBalance = '-18811077572130500000';
      const expectedBaseBalance = 39913423321n - 1n;

      // const expectedSumB = ((2494598646n*(1n<<128n))/(10n**13n))+1n;
      const expectedSumB = 2494598646462n;
      const expectedSumA = 2345128n;
      const expectedSumFp = 19019671n;
      const expectedSumFee = 5300982n;

      const expectedTickSumB = 1189490198145n;
      const expectedTickSumA = 746151n;
      const expectedTickSumFp = 0n;
      const expectedTickSumFee = 2542858n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 20767051316n;
      const expectedFundingPayment = 143421n + 1n;

      const expectedAccount1UnrealizedFunding = 0n;
      const expectedAccount1UnrealizedFee = 0n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2101.73847049388, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050', async () => {
      const startTick = -199820;
      const endTick = -200050;

      const swapTokenAmount = '-24716106801005000000';
      const expectedTokenBalance = '-43527184373135500000';

      //TODO: Check
      const expectedBaseBalance = 91163779610n - 1n;

      const expectedSumB = 5018049315957n + 1n;
      const expectedSumA = 3195846n;
      const expectedSumFp = 40241668n;
      const expectedSumFee = 10541355n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 51250196260n;
      const expectedFundingPayment = 160028n + 1n;

      const expectedTickSumB = 1305108448316n+3n;
      const expectedTickSumA = 2345128n;
      const expectedTickSumFp = 0n;
      const expectedTickSumFee = 2758123n;

      const expectedAccount1UnrealizedFunding = 0n;
      const expectedAccount1UnrealizedFee = 0n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2053.95251980329, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Long  ETH : Price Changes (StartTick = -200050, EndTick = -199820', async () => {
      const startTick = -200050;
      const endTick = -199820;

      const swapTokenAmount = '24716106801005000000';
      const expectedTokenBalance = '-18811077572130500000';

      const expectedBaseBalance = 39759963661n - 3n;

      const expectedSumB = 2494598646462n;
      const expectedSumA = 4027221n;
      const expectedSumFp = 81960507n;
      const expectedSumFee = 15781728n + 1n;

      const expectedTickSumB = 1305108448316n;
      const expectedTickSumA = 2345128n;
      const expectedTickSumFp = 0n;
      const expectedTickSumFee = 2758123n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = -51404177823n - 2n;
      const expectedFundingPayment = 361873n + 1n;

      const expectedAccount1UnrealizedFunding = 0n;
      const expectedAccount1UnrealizedFee = 11810983n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2101.73847049388, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Long  ETH : Price Changes (StartTick = -199820, EndTick = -199540', async () => {
      const startTick = -199820;
      //TODO: Check
      const endTick = -199540 - 1;

      const swapTokenAmount = '22871896768962800000';
      const expectedTokenBalance = '4060819196832300000';

      const expectedBaseBalance = -9037007285n - 4n;

      const expectedSumB = -538518542231n;
      const expectedSumA = 4999470n;
      const expectedSumFp = 106214217n + 1n;
      const expectedSumFee = 22243187n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = -48797153836n - 1n;
      const expectedFundingPayment = 182889n + 1n;

      const expectedTickSumB = 189490198145n;
      const expectedTickSumA = 4027221n;
      const expectedTickSumFp = 60007362n;
      const expectedTickSumFee = 13023604n;

      const expectedAccount1UnrealizedFunding = 47285n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2161.41574705594, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199540, EndTick = -199820', async () => {
      const startTick = -199540 - 1;
      const endTick = -199820;

      const swapTokenAmount = '-22871896768962800000';
      const expectedTokenBalance = '-18811077572130500000';

      const expectedBaseBalance = 39613949988n - 4n;

      const expectedSumB = 2494598646462n;
      const expectedSumA = 5599294n;
      const expectedSumFp = 102984058n + 1n;
      const expectedSumFee = 28704645n + 1n;

      const expectedTickSumB = 189490198145n;
      const expectedTickSumA = 4027221n;
      const expectedTickSumFp = 60007362n;
      const expectedTickSumFee = 13023604n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 48650981631n - 1n;
      const expectedFundingPayment = -24358n + 1n;

      const expectedAccount1UnrealizedFunding = 47285n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2141.33749022076, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050', async () => {
      const startTick = -199820;
      const endTick = -200050;

      const swapTokenAmount = '-24716106801005000000';
      //TODO: Correction in finquant test cases
      const expectedTokenBalance = '-43527184373135500000';

      const expectedBaseBalance = 90864172645n - 4n;

      const expectedSumB = 5018049315957n + 1n;
      const expectedSumA = 5739622n;
      const expectedSumFp = 106484699n + 1n;
      const expectedSumFee = 33945018n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 51250196260n;
      const expectedFundingPayment = 26396n + 1n;

      const expectedTickSumB = 1305108448316n;
      const expectedTickSumA = 5599294n;
      const expectedTickSumFp = 24277051n;
      const expectedTickSumFee = 15681040n;

      const expectedAccount1UnrealizedFunding = 47285n;
      const expectedAccount1UnrealizedFee = 23621967n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2053.95251980329, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200050, EndTick = -200310', async () => {
      const startTick = -200050;
      const endTick = -200310;

      const swapTokenAmount = '-28284342105582900000';
      const expectedTokenBalance = '-71811526478718400000';
      const expectedBaseBalance = 148094287097n - 4n;

      const expectedSumB = 7905807594282n + 1n;
      const expectedSumA = 6570998n;
      const expectedSumFp = 148203538n + 1n;
      const expectedSumFee = 39796806n + 1n;

      const expectedTickSumB = 1305108448316n;
      const expectedTickSumA = 5599294n;
      const expectedTickSumFp = 24277051n;
      const expectedTickSumFee = 15681040n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 57229752578n;
      const expectedFundingPayment = 361873n + 1n;

      const expectedAccount1UnrealizedFunding = 7285n;
      const expectedAccount1UnrealizedFee = 35432951n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
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
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2001.24061387234, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[1] Removes Liq b/w ticks (-200310 to -199820) @ tickCurrent = -200310', async () => {
      const tickLower = -200310;
      const tickUpper = -199820;
      const liquidityDelta = -22538439850760800n;
      const limitOrderType = 0;
      const expectedEndTokenBalance = 12196020739034000000n;
      const expectedEndBaseBalance = '-24951543170';

      const expectedSumALast = 6570998n;
      const expectedSumBLast = -115618250170n;
      const expectedSumFpLast = 32327135n;
      const expectedSumFeeLast = 21572907n;

      const expectedAccount1UnrealizedFunding = 94570n;
      const expectedAccount1UnrealizedFee = 48621967n;

      await updateRangeOrderAndCheck(
        user1,
        user1AccountNo,
        vTokenAddress,
        vBaseAddress,
        tickLower,
        tickUpper,
        liquidityDelta,
        false,
        limitOrderType,
        0,
        1,
        expectedEndTokenBalance,
        expectedEndBaseBalance,
        true,
        expectedSumALast,
        expectedSumBLast,
        expectedSumFpLast,
        expectedSumFeeLast,
      );

      await checkUnrealizedFundingPaymentAndFee(
        user1AccountNo,
        vTokenAddress,
        0,
        expectedAccount1UnrealizedFunding,
        expectedAccount1UnrealizedFee,
      );
    });

    it('Timestamp and Oracle Update - 6200', async () => {
      const timestampIncrease = 6200;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(2001.24061387234, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200310, EndTick = -200460', async () => {
      const startTick = -200310;
      const endTick = -200460;

      const swapTokenAmount = '-12692319513534700000';
      const expectedTokenBalance = '-84503845992253100000';
      const expectedBaseBalance = 173255240934n - 4n;

      const expectedSumB = 9588977681563n;
      const expectedSumA = 7612477n;
      const expectedSumFp = 230540892n + 1n;
      const expectedSumFee = 43138396n + 1n;

      const expectedTickSumB = 6716317396136n;
      const expectedTickSumA = 6570998n;
      const expectedTickSumFp = 78917555n;
      const expectedTickSumFee = 37253947n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 25160205935n;
      const expectedFundingPayment = 747901n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
      await checkTickParams(-200, expectedTickSumB, expectedTickSumA, expectedTickSumFp, expectedTickSumFee);
    });

    it('Timestamp and Oracle Update - 6300', async () => {
      const timestampIncrease = 6300;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1991.25998215442, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200460, EndTick = -200610', async () => {
      const startTick = -200460;
      const endTick = -200610;

      const swapTokenAmount = '-12787864980350100000';
      const expectedTokenBalance = '-97291710972603200000';
      const expectedBaseBalance = 198227557862n - 4n;

      const expectedSumB = 11284818366330n;
      const expectedSumA = 7727632n;
      const expectedSumFp = 241583015n + 1n;
      const expectedSumFee = 46455018n + 2n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 24972219619n;
      const expectedFundingPayment = 97308n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });

    it('Timestamp and Oracle Update - 7200', async () => {
      const timestampIncrease = 7200;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1942.0979282388, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200610, EndTick = -200750', async () => {
      const startTick = -200610;
      const endTick = -200750;

      const swapTokenAmount = '-12022178314034100000';
      const expectedTokenBalance = '-109313889286637300000';
      const expectedBaseBalance = 221367579949n - 4n;

      const expectedSumB = 12879118832888n + 1n;
      const expectedSumA = 8738332n;
      const expectedSumFp = 355638731n + 1n;
      const expectedSumFee = 49528172n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 23139038760n;
      const expectedFundingPayment = 983326n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });

    it('Timestamp and Oracle Update - 7600', async () => {
      const timestampIncrease = 7600;
      await network.provider.send('evm_setNextBlockTimestamp', [initialBlockTimestamp + timestampIncrease]);
      vPoolWrapper.setBlockTimestamp(timestampIncrease);
      const realSqrtPrice = await priceToSqrtPriceX96(1915.09933823398, vBase, vToken);
      oracle.setSqrtPrice(realSqrtPrice);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(timestampIncrease);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -200750, EndTick = -200800', async () => {
      const startTick = -200750;
      const endTick = -200800;

      const swapTokenAmount = '-4314069685093700000';
      const expectedTokenBalance = '-113627958971731000000';
      const expectedBaseBalance = 229592833231n - 4n;

      const expectedSumB = 13451221752347n + 1n;
      const expectedSumA = 9181288n;
      const expectedSumFp = 412687502n + 2n;
      const expectedSumFee = 50620524n + 1n;

      const expectedTokenAmountOut = swapTokenAmount;
      const expectedBaseAmountOutWithFee = 8224769071n;
      const expectedFundingPayment = 484210n + 1n;

      const swapTxn = await swapTokenAndCheck(
        user2,
        user2AccountNo,
        vTokenAddress,
        vBaseAddress,
        swapTokenAmount,
        0,
        false,
        false,
        startTick,
        endTick,
        expectedTokenBalance,
        expectedBaseBalance,
        expectedTokenAmountOut,
        expectedBaseAmountOutWithFee,
        expectedFundingPayment,
      );

      await checkGlobalParams(expectedSumB, expectedSumA, expectedSumFp, expectedSumFee);
    });
  });
});
