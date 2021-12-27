import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ethers, providers } from 'ethers';

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
} from '../typechain-types';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';

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
} from './utils/price-tick';

import { smock } from '@defi-wonderland/smock';
import { ADDRESS_ZERO, priceToClosestTick } from '@uniswap/v3-sdk';
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
    sumALastX128?: BigNumberish,
    sumBInsideLastX128?: BigNumberish,
    sumFpInsideLastX128?: BigNumberish,
    sumFeeInsideLastX128?: BigNumberish,
  ) {
    const out = await clearingHouseTest.getAccountLiquidityPositionDetails(accountNo, vTokenAddress, num);
    if (typeof tickLower !== 'undefined') expect(out.tickLower).to.eq(tickLower);
    if (typeof tickUpper !== 'undefined') expect(out.tickUpper).to.eq(tickUpper);
    if (typeof limitOrderType !== 'undefined') expect(out.limitOrderType).to.eq(limitOrderType);
    if (typeof liquidity !== 'undefined') expect(out.liquidity).to.eq(liquidity);
    if (typeof sumALastX128 !== 'undefined') expect(out.sumALastX128).to.eq(sumALastX128);
    if (typeof sumBInsideLastX128 !== 'undefined') expect(out.sumBInsideLastX128).to.eq(sumBInsideLastX128);
    if (typeof sumFpInsideLastX128 !== 'undefined') expect(out.sumFpInsideLastX128).to.eq(sumFpInsideLastX128);
    if (typeof sumFeeInsideLastX128 !== 'undefined') expect(out.sumFeeInsideLastX128).to.eq(sumFeeInsideLastX128);
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
  ) {
    const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(tokenAddress);
    const swapParams = {
      amount: amount,
      sqrtPriceLimit: sqrtPriceLimit,
      isNotional: isNotional,
      isPartialAllowed: isPartialAllowed,
    };
    await clearingHouseTest.connect(user).swapToken(userAccountNo, truncatedAddress, swapParams);
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
  ) {
    //TODO: Check if below check is wrong
    await checkVirtualTick(expectedStartTick);
    await swapToken(user, userAccountNo, tokenAddress, amount, sqrtPriceLimit, isNotional, isPartialAllowed);

    //TODO: Check if below check is wrong
    await checkVirtualTick(expectedEndTick);
    await checkTokenBalance(user2AccountNo, tokenAddress, expectedEndTokenBalance);
    await checkTokenBalance(user2AccountNo, baseAddress, expectedEndBaseBalance);
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
    );
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
    const vBase = await vBaseFactory.deploy(REAL_BASE);
    vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user0 = signers[1];
    user1 = signers[2];
    user2 = signers[3];

    const initialMargin = 20_000;
    const maintainanceMargin = 10_000;
    const timeHorizon = 1;
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
      POOL_BYTE_CODE_HASH,
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
    vPool = await hre.ethers.getContractAt('IUniswapV3Pool', out.vPool);
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

    console.log('### Is VToken 0 ? ###');
    console.log(BigNumber.from(vTokenAddress).lt(vBaseAddress));
    console.log(vTokenAddress);
    console.log(vBaseAddress);
    console.log('### Base decimals ###');
    console.log(await vBase.decimals());
    console.log('Initial Price');
    console.log(await sqrtPriceX96ToPrice(await oracle.getTwapSqrtPriceX96(0), vBase, vToken));
    console.log(sqrtPriceX96ToTick(await oracle.getTwapSqrtPriceX96(0)));

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

  // describe('#Deposit', async () => {

  //   it('Account 2', async () => {
  //     await rBase.connect(user1).approve(clearingHouseTest.address, tokenAmount(10n ** 5n, 6));
  //     const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
  //     await clearingHouseTest
  //       .connect(user1)
  //       .addMargin(user1AccountNo, truncatedVBaseAddress, tokenAmount(10n ** 5n, 6));
  //     checkRealBaseBalance(user1.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
  //     checkRealBaseBalance(clearingHouseTest.address, tokenAmount(2n * 10n ** 5n, 6));
  //     await checkDepositBalance(user0AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
  //   });
  //   it('Account 3', async () => {
  //     await rBase.connect(user2).approve(clearingHouseTest.address, tokenAmount(10n ** 5n, 6));
  //     const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
  //     await clearingHouseTest
  //       .connect(user2)
  //       .addMargin(user2AccountNo, truncatedVBaseAddress, tokenAmount(10n ** 5n, 6));
  //     checkRealBaseBalance(user2.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
  //     checkRealBaseBalance(clearingHouseTest.address, tokenAmount(3n * 10n ** 5n, 6));
  //     await checkDepositBalance(user0AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
  //   });
  // });

  describe('#Scenario 1', async () => {
    beforeEach(async () => {
      const { sqrtPriceX96 } = await vPool.slot0();
      oracle.setSqrtPrice(sqrtPriceX96);
    });
    it('Timestamp Update - 0', async () => {
      vPoolWrapper.setBlockTimestamp(0);
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
      const expectedTokenBalance = tokenAmount(-18596, 18).div(1000);
      const expectedBaseBalance = '-208523902880';

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
      );
    });
    it('Timestamp Update - 600', async () => {
      vPoolWrapper.setBlockTimestamp(600);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(600);
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

      const swapTokenAmount = '-8969616182683630000';
      //TODO: Correction in finquant test cases
      const expectedTokenBalance = '-8969616182683630000';
      const expectedBaseBalance = '19146228583';

      await swapTokenAndCheck(
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
      );
    });
    it('Acct[1] Initial Collateral Deposit = 100K USDC', async () => {
      await addMargin(user1, user1AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
      await checkRealBaseBalance(user1.address, tokenAmount(10n ** 6n - 10n ** 5n, 6));
      await checkRealBaseBalance(clearingHouseTest.address, tokenAmount(3n * 10n ** 5n, 6));
      await checkDepositBalance(user1AccountNo, vBaseAddress, tokenAmount(10n ** 5n, 6));
    });
    it('Timestamp Update - 1200', async () => {
      vPoolWrapper.setBlockTimestamp(1200);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(1200);
    });
    it('Acct[1] Adds Liq b/w ticks (-200310 to -199820) @ tickCurrent = -199700', async () => {
      const tickLower = -200310;
      const tickUpper = -199820;
      const liquidityDelta = 22538439850760800n;
      const limitOrderType = 0;
      const expectedEndTokenBalance = 0;
      const expectedEndBaseBalance = tokenAmount('-25000', 6);

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
      );
    });

    it('Timestamp Update - 1900', async () => {
      vPoolWrapper.setBlockTimestamp(1900);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(1900);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199700, EndTick = -199820)', async () => {
      const startTick = -199700;
      const endTick = -199820;

      const swapTokenAmount = '-9841461389446880000';
      //TODO: Correction in finquant test cases
      const expectedTokenBalance = '-18811077572130510000';
      const expectedBaseBalance = '39913423323';

      await swapTokenAndCheck(
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
      );
    });

    it('Timestamp Update - 2600', async () => {
      vPoolWrapper.setBlockTimestamp(2600);
      expect(await vPoolWrapper.blockTimestamp()).to.eq(2600);
    });

    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050', async () => {
      const startTick = -199820;
      const endTick = -200050;

      const swapTokenAmount = '-24716106801005000000';
      //TODO: Correction in finquant test cases
      const expectedTokenBalance = '-43527184373135510000';
      const expectedBaseBalance = '91687997289';

      await swapTokenAndCheck(
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
      );
    });
    it('Acct[2] Long  ETH : Price Changes (StartTick = -200050, EndTick = -199820');
    it('Acct[2] Long  ETH : Price Changes (StartTick = -199820, EndTick = -199540');
    it('Acct[2] Short ETH : Price Changes (StartTick = -199540, EndTick = -199820');
    it('Acct[2] Short ETH : Price Changes (StartTick = -199820, EndTick = -200050');
    it('Acct[2] Short ETH : Price Changes (StartTick = -200050, EndTick = -200310');
    it('Acct[1] Removes Liq b/w ticks (-200310 to -199820) @ tickCurrent = -200310');
    it('Acct[2] Short ETH : Price Changes (StartTick = -200310, EndTick = -200460');
    it('Acct[2] Short ETH : Price Changes (StartTick = -200460, EndTick = -200610');
    it('Acct[2] Short ETH : Price Changes (StartTick = -200610, EndTick = -200750');
    it('Acct[2] Short ETH : Price Changes (StartTick = -200750, EndTick = -200800');
  });

  //   async function liquidityChange(user: SignerWithAddress, accountNo:BigNumberish, vTokenAddress:string, tickLower: number, tickUpper: number, liquidityDelta: BigNumberish) {

  //     const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);

  //     const priceLowerActual = await tickToPrice(tickLower, vBase, vToken);
  //     const priceUpperActual = await tickToPrice(tickUpper, vBase, vToken);
  //     // console.log(
  //     //   `adding liquidity between ${priceLowerActual} (tick: ${tickLower}) and ${priceUpperActual} (tick: ${tickUpper})`,
  //     // );
  //     const liquidityChangeParams = {
  //         tickLower: tickLower,
  //         tickUpper: tickUpper,
  //         liquidityDelta: liquidityDelta,
  //         closeTokenPosition: false,
  //         limitOrderType: 0,
  //         sqrtPriceCurrent: 0,
  //         slippageToleranceBps: 0,
  //     };
  //     await clearingHouseTest.connect(user).updateRangeOrder(accountNo, truncatedAddress, liquidityChangeParams);
  //   }
});
