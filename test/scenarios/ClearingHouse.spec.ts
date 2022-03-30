import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ethers } from 'ethers';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

import { activateMainnetFork, deactivateMainnetFork } from '../helpers/mainnet-fork';
import { getCreateAddressFor } from '../helpers/create-addresses';
import {
  AccountTest,
  RageTradeFactory,
  ClearingHouse,
  ERC20,
  RealTokenMock,
  OracleMock,
  IERC20,
  ClearingHouseTest,
  IUniswapV3Pool,
  Account,
  VPoolWrapper,
} from '../../typechain-types';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  SETTLEMENT_TOKEN,
} from '../helpers/realConstants';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { stealFunds, parseTokenAmount } from '../helpers/stealFunds';
import { priceToSqrtPriceX96, sqrtPriceX96ToTick } from '../helpers/price-tick';

import { smock } from '@defi-wonderland/smock';
import { ADDRESS_ZERO } from '@uniswap/v3-sdk';
import { randomAddress } from '../helpers/random';
import { IClearingHouseStructures } from '../../typechain-types/artifacts/contracts/protocol/clearinghouse/ClearingHouse';
import { truncate } from '../helpers/vToken';
import { parseUnits } from '@ethersproject/units';
const whaleFosettlementToken = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

config();
const { ALCHEMY_KEY } = process.env;

describe('Clearing House Library', () => {
  let test: AccountTest;

  let vQuoteAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  // let constants: ConstantsStruct;
  let clearingHouseTest: ClearingHouseTest;
  let vPool: IUniswapV3Pool;

  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user1AccountNo: BigNumberish;
  let user2AccountNo: BigNumberish;

  let settlementToken: IERC20;
  let settlementTokenOracle: OracleMock;

  let settlementToken1: IERC20;
  let settlementToken1Oracle: OracleMock;

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

  async function checkLiquidityPositionNum(vTokenAddress: string, num: BigNumberish) {
    const outNum = await clearingHouseTest.getAccountLiquidityPositionNum(0, vTokenAddress);
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
    const out = await clearingHouseTest.getAccountLiquidityPositionDetails(0, vTokenAddress, num);
    if (typeof tickLower !== 'undefined') expect(out.tickLower).to.eq(tickLower);
    if (typeof tickUpper !== 'undefined') expect(out.tickUpper).to.eq(tickUpper);
    if (typeof limitOrderType !== 'undefined') expect(out.limitOrderType).to.eq(limitOrderType);
    if (typeof liquidity !== 'undefined') expect(out.liquidity).to.eq(liquidity);
    if (typeof sumALastX128 !== 'undefined') expect(out.sumALastX128).to.eq(sumALastX128);
    if (typeof sumBInsideLastX128 !== 'undefined') expect(out.sumBInsideLastX128).to.eq(sumBInsideLastX128);
    if (typeof sumFpInsideLastX128 !== 'undefined') expect(out.sumFpInsideLastX128).to.eq(sumFpInsideLastX128);
    if (typeof sumFeeInsideLastX128 !== 'undefined') expect(out.sumFeeInsideLastX128).to.eq(sumFeeInsideLastX128);
  }

  async function initializePool(
    rageTradeFactory: RageTradeFactory,
    initialMarginRatioBps: BigNumberish,
    maintainanceMarginRatioBps: BigNumberish,
    twapDuration: BigNumberish,
    initialPrice: BigNumberish,
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    await oracle.setSqrtPriceX96(initialPrice);

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
      liquidityFeePips: 500,
      protocolFeePips: 500,
      slotsToInitialize: 100,
    });

    const eventFilter = rageTradeFactory.filters.PoolInitialized();
    const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    return { vTokenAddress, realToken, oracle, vPool };
  }

  before(async () => {
    await activateMainnetFork();

    dummyTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(148392483294).toHexString(), 20);

    settlementToken = await hre.ethers.getContractAt('IERC20', SETTLEMENT_TOKEN);

    // const vQuoteFactory = await hre.ethers.getContractFactory('VQuote');
    // const vQuote = await vQuoteFactory.deploy(SETTLEMENT_TOKEN);
    // vQuoteAddress = vQuote.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user1 = signers[1];
    user2 = signers[2];

    const futureVPoolFactoryAddress = await getCreateAddressFor(admin, 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(admin, 4);

    // const VPoolWrapperDeployer = await (
    //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    // ).deploy(futureVPoolFactoryAddress);

    let accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const clearingHouseTestLogic = await (
      await hre.ethers.getContractFactory('ClearingHouseTest', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy();

    let vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

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

    clearingHouseTest = await hre.ethers.getContractAt('ClearingHouseTest', await rageTradeFactory.clearingHouse());

    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouseTest.insuranceFund());
    hre.tracer.nameTags[insuranceFund.address] = 'insuranceFund';

    const vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());
    vQuoteAddress = vQuote.address;

    // await vQuote.transferOwnership(VPoolFactory.address);
    // const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    // realToken = await realTokenFactory.deploy();

    let out = await initializePool(
      rageTradeFactory,
      2000,
      1000,
      1,
      await priceToSqrtPriceX96(4000, 6, 18),
      // .div(60 * 10 ** 6),
    );

    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;
    vPool = (await hre.ethers.getContractAt(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      out.vPool,
    )) as IUniswapV3Pool;

    let out1 = await initializePool(
      rageTradeFactory,
      2000,
      1000,
      1,
      await priceToSqrtPriceX96(4000, 6, 18),
      // .div(60 * 10 ** 6),
    );
    vTokenAddress1 = out1.vTokenAddress;

    // console.log('### Is VToken 0 ? ###');
    // console.log(BigNumber.from(vTokenAddress).lt(vQuoteAddress));
    // console.log(vTokenAddress);
    // console.log(vQuoteAddress);
    // console.log('###VQuote decimals ###');
    // console.log(await vQuote.decimals());

    // constants = await VPoolFactory.constants();
    settlementTokenOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    settlementToken1 = await hre.ethers.getContractAt('IERC20', '0x6B175474E89094C44Da98b954EedeAC495271d0F');
    settlementToken1Oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
    await clearingHouseTest.updateCollateralSettings(settlementToken.address, {
      oracle: settlementTokenOracle.address,
      twapDuration: 300,
      isAllowedForDeposit: false,
    });

    await clearingHouseTest.updateCollateralSettings(settlementToken1.address, {
      oracle: settlementToken1Oracle.address,
      twapDuration: 300,
      isAllowedForDeposit: false,
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

      expect(protocol.minRequiredMargin).eq(minRequiredMargin);
      expect(protocol.liquidationParams.rangeLiquidationFeeFraction).eq(liquidationParams.rangeLiquidationFeeFraction);
      expect(protocol.liquidationParams.tokenLiquidationFeeFraction).eq(liquidationParams.tokenLiquidationFeeFraction);
      expect(protocol.liquidationParams.insuranceFundFeeShareBps).eq(liquidationParams.insuranceFundFeeShareBps);

      expect(protocol.removeLimitOrderFee).eq(removeLimitOrderFee);
      expect(protocol.minimumOrderNotional).eq(minimumOrderNotional);
      expect(curPaused).to.be.false;
    });
  });

  describe('#StealFunds', () => {
    it('Steal Funds', async () => {
      await stealFunds(SETTLEMENT_TOKEN, 6, user1.address, '1000000', whaleFosettlementToken);
      await stealFunds(settlementToken1.address, 6, user1.address, '1000000', whaleFosettlementToken);
      await stealFunds(SETTLEMENT_TOKEN, 6, user2.address, 10 ** 6, whaleFosettlementToken);
      expect(await settlementToken.balanceOf(user1.address)).to.eq(parseTokenAmount('1000000', 6));
      expect(await settlementToken.balanceOf(user2.address)).to.eq(parseTokenAmount(10 ** 6, 6));
    });
  });

  describe('#AccountCreation', () => {
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user1).createAccount();
      user1AccountNo = 0;
      expect(await clearingHouseTest.numAccounts()).to.eq(1);
      expect(await clearingHouseTest.getAccountOwner(user1AccountNo)).to.eq(user1.address);
      // expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user1AccountNo)).to.eq(user1AccountNo);
    });
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user2).createAccount();
      user2AccountNo = 1;
      expect(await clearingHouseTest.numAccounts()).to.eq(2);
      expect(await clearingHouseTest.getAccountOwner(user2AccountNo)).to.eq(user2.address);
      // expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user2AccountNo)).to.eq(user2AccountNo);
    });
  });

  describe('#InitializeToken', () => {
    it('vToken Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokens(vTokenAddress)).to.eq(vTokenAddress);
    });
    // it('vQuote Intialized', async () => {
    //   expect(await clearingHouseTest.getTokenAddressInVTokens(vQuoteAddress)).to.eq(vQuoteAddress);
    // });
    it('Other Address Not Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokens(dummyTokenAddress)).to.eq(ADDRESS_ZERO);
    });
  });

  describe('#TokenSupport', () => {
    before(async () => {
      expect((await clearingHouseTest.getPoolInfo(truncate(vTokenAddress))).settings.isAllowedForTrade).to.be.false;
      expect((await clearingHouseTest.getCollateralInfo(truncate(realToken.address))).settings.isAllowedForDeposit).to
        .be.false;
      expect((await clearingHouseTest.getPoolInfo(truncate(vQuoteAddress))).settings.isAllowedForTrade).to.be.false;
      expect((await clearingHouseTest.getPoolInfo(truncate(settlementToken.address))).settings.isAllowedForTrade).to.be
        .false;
      // expect(await clearingHouseTest.supportedVTokens(vQuoteAddress)).to.be.false;
      // expect(await clearingHouseTest.supportedDeposits(settlementToken.address)).to.be.false;
    });
    it('Add Token Position Support - Fail - Unauthorized', async () => {
      const settings = await getPoolSettings(vTokenAddress);
      settings.isAllowedForTrade = true;
      await expect(
        clearingHouseTest.connect(user1).updatePoolSettings(truncate(vTokenAddress), settings),
      ).to.be.revertedWith('Unauthorised()');
    });
    it('Add Token Position Support - Pass', async () => {
      const settings = await getPoolSettings(vTokenAddress);
      settings.isAllowedForTrade = true;
      await clearingHouseTest.connect(admin).updatePoolSettings(truncate(vTokenAddress), settings);
      expect((await clearingHouseTest.getPoolInfo(truncate(vTokenAddress))).settings.isAllowedForTrade).to.be.true;
    });
    it('Add Token Deposit Support - Fail - Unauthorized', async () => {
      const { settings } = await getCollateralSettings(realToken.address);
      settings.isAllowedForDeposit = true;
      await expect(
        clearingHouseTest.connect(user1).updateCollateralSettings(realToken.address, settings),
      ).to.be.revertedWith('Unauthorised()');
    });
    // it('Add Token Deposit Support - Uninitialized Collateral', async () => {
    //   await expect(clearingHouseTest.connect(admin).updateSupportedDeposits(vTokenAddress, true)).to.be.revertedWith(
    //     'Invalid Address',
    //   );
    // });
    it('AddVQuote Deposit Support  - Pass', async () => {
      const { settings } = await getCollateralSettings(settlementToken.address);
      settings.isAllowedForDeposit = true;
      await clearingHouseTest.connect(admin).updateCollateralSettings(settlementToken.address, settings);
      expect((await getCollateralSettings(settlementToken.address)).settings.isAllowedForDeposit).to.be.true;
    });
  });

  describe('#Pause Check', () => {
    let amount: BigNumber;
    let truncatedAddress: number;
    let swapParams: any;
    let liquidityChangeParams: any;

    let fundingPaymentStateUpdatedTopicHash: string;
    let poolIds: string[];
    let poolsSumAValueAfterPause: BigNumber[];

    before(async () => {
      amount = parseTokenAmount('1000000', 6);
      truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      swapParams = {
        amount: parseTokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      liquidityChangeParams = {
        tickLower: 100,
        tickUpper: 100,
        liquidityDelta: 10n ** 19n,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };

      poolIds = [truncate(vTokenAddress), truncate(vTokenAddress1)];

      const fp = await hre.ethers.getContractAt('FundingPayment', ethers.constants.AddressZero);
      fundingPaymentStateUpdatedTopicHash = fp.filters.FundingPaymentStateUpdated().topics?.[0] as string;
    });

    it('Pause', async () => {
      const tx = await clearingHouseTest.pause(poolIds);

      const curPaused = await clearingHouseTest.paused();
      expect(curPaused).to.be.true;

      // checks if the funding payment state updated event is emitted for all the pools
      const rc = await tx.wait();
      expect(rc.events?.filter(val => (val.topics[0] as string) === fundingPaymentStateUpdatedTopicHash).length).to.eq(
        poolIds.length,
      );

      poolsSumAValueAfterPause = await getPoolsSumA(poolIds);
    });

    it('Create Account', async () => {
      await expect(clearingHouseTest.createAccount()).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Deposit', async () => {
      expect(
        clearingHouseTest.connect(user1).updateMargin(user1AccountNo, truncatedAddress, amount),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Withdraw', async () => {
      await expect(
        clearingHouseTest.connect(user1).updateMargin(user1AccountNo, truncatedAddress, amount.mul(-1)),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Profit', async () => {
      await expect(clearingHouseTest.connect(user1).updateProfit(user1AccountNo, amount)).to.be.revertedWith(
        'Pausable: paused',
      );
      await clearingHouseTest.paused();
    });

    it('Token Position', async () => {
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Range Position', async () => {
      await expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Token Liquidation', async () => {
      await expect(
        clearingHouseTest.connect(user2).liquidateTokenPosition(user1AccountNo, truncatedAddress),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('Range Liquidation', async () => {
      await expect(clearingHouseTest.connect(user2).liquidateLiquidityPositions(user1AccountNo)).to.be.revertedWith(
        'Pausable: paused',
      );
      await clearingHouseTest.paused();
    });

    it('Remove Limit Order', async () => {
      await expect(
        clearingHouseTest.connect(user2).removeLimitOrder(user1AccountNo, truncatedAddress, -100, 100),
      ).to.be.revertedWith('Pausable: paused');
      await clearingHouseTest.paused();
    });

    it('UnPause', async () => {
      const tx = await clearingHouseTest.unpause([truncate(vTokenAddress), truncate(vTokenAddress1)]);
      const curPaused = await clearingHouseTest.paused();

      expect(curPaused).to.be.false;

      // checks if the funding payment state updated event is emitted for all the pools
      const rc = await tx.wait();
      expect(rc.events?.filter(val => (val.topics[0] as string) === fundingPaymentStateUpdatedTopicHash).length).to.eq(
        poolIds.length,
      );

      // some time is elapsed between test cases but still sumA should stay the same
      const poolsSumAValueAfterUnpause = await getPoolsSumA(poolIds);
      expect(poolsSumAValueAfterUnpause).to.deep.equal(poolsSumAValueAfterPause);
    });
  });

  describe('#Deposit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vQuoteAddress);
      await expect(
        clearingHouseTest.connect(user2).updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      await expect(
        clearingHouseTest.connect(user1).updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('1000000', 6)),
      ).to.be.revertedWith('CollateralDoesNotExist(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken1.address);
      await expect(
        clearingHouseTest.connect(user1).updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('1000000', 6)),
      ).to.be.revertedWith('CollateralNotAllowedForUse(' + +truncate(settlementToken1.address) + ')');
    });
    it('Pass', async () => {
      await settlementToken.connect(user1).approve(clearingHouseTest.address, parseTokenAmount('1000000', 6));
      const truncatedSettlementTokenAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      await clearingHouseTest
        .connect(user1)
        .updateMargin(user1AccountNo, truncatedSettlementTokenAddress, parseTokenAmount('1000000', 6));
      expect(await settlementToken.balanceOf(user1.address)).to.eq(parseTokenAmount('0', 6));
      expect(await settlementToken.balanceOf(clearingHouseTest.address)).to.eq(parseTokenAmount('1000000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, settlementToken.address)).to.eq(
        parseTokenAmount('1000000', 6),
      );

      const accountInfo = await clearingHouseTest.getAccountInfo(user1AccountNo);
      expect(accountInfo.collateralDeposits[0].collateral.toLowerCase()).to.eq(settlementToken.address);
      expect(accountInfo.collateralDeposits[0].balance).to.eq(parseTokenAmount('1000000', 6));
    });
  });
  describe('#Withdraw', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      await expect(
        clearingHouseTest
          .connect(user2)
          .updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('-1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      await expect(
        clearingHouseTest
          .connect(user1)
          .updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('-1000000', 6)),
      ).to.be.revertedWith('CollateralDoesNotExist(' + truncatedAddress + ')');
    });

    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      await clearingHouseTest
        .connect(user1)
        .updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('-100000', 6));
      expect(await settlementToken.balanceOf(user1.address)).to.eq(parseTokenAmount('100000', 6));
      expect(await settlementToken.balanceOf(clearingHouseTest.address)).to.eq(parseTokenAmount('900000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, settlementToken.address)).to.eq(
        parseTokenAmount('900000', 6),
      );
    });

    it('Pass - Withdrawal after removal of token support', async () => {
      //Add settlementToken1 support
      const { settings } = await getCollateralSettings(settlementToken1.address);
      settings.isAllowedForDeposit = true;
      await clearingHouseTest.connect(admin).updateCollateralSettings(settlementToken1.address, settings);
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken1.address);

      await settlementToken1.connect(user1).approve(clearingHouseTest.address, parseTokenAmount('1000000', 6));
      await clearingHouseTest
        .connect(user1)
        .updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('1000000', 6));
      expect(await settlementToken1.balanceOf(user1.address)).to.eq(0);
      expect(await settlementToken1.balanceOf(clearingHouseTest.address)).to.eq(parseTokenAmount('1000000', 6));

      //Remove settlementToken1 support
      settings.isAllowedForDeposit = false;
      await clearingHouseTest.connect(admin).updateCollateralSettings(settlementToken1.address, settings);

      await clearingHouseTest
        .connect(user1)
        .updateMargin(user1AccountNo, truncatedAddress, parseTokenAmount('-1000000', 6));

      expect(await settlementToken1.balanceOf(user1.address)).to.eq(parseTokenAmount('1000000', 6));
      expect(await settlementToken1.balanceOf(clearingHouseTest.address)).to.eq(0);
    });
  });

  describe('#Profit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      await expect(
        clearingHouseTest.connect(user2).updateProfit(user1AccountNo, parseTokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });

    it('Pass - Cover Loss', async () => {
      await settlementToken.connect(user1).approve(clearingHouseTest.address, parseTokenAmount('100000', 6));
      await clearingHouseTest.connect(user1).updateProfit(user1AccountNo, parseTokenAmount('100000', 6));
      expect(await settlementToken.balanceOf(user1.address)).to.eq(0);
      expect(await settlementToken.balanceOf(clearingHouseTest.address)).to.eq(parseTokenAmount('1000000', 6));
      const accountTokenPosition = await clearingHouseTest.functions.getAccountQuoteBalance(user1AccountNo);
      expect(accountTokenPosition.balance).to.eq(parseTokenAmount('100000', 6));
    });

    it('Pass - Remove Profit', async () => {
      await clearingHouseTest.connect(user1).updateProfit(user1AccountNo, -parseTokenAmount('100000', 6));
      expect(await settlementToken.balanceOf(user1.address)).to.eq(parseTokenAmount('100000', 6));
      expect(await settlementToken.balanceOf(clearingHouseTest.address)).to.eq(parseTokenAmount('900000', 6));
      const accountTokenPosition = await clearingHouseTest.functions.getAccountQuoteBalance(user1AccountNo);
      expect(accountTokenPosition.balance).to.eq(0);
    });
  });
  describe('#InitLiquidity', async () => {
    it('#InitLiquidity', async () => {
      await settlementToken.connect(user2).approve(clearingHouseTest.address, parseTokenAmount(10 ** 6, 6));
      const truncatedSettlementTokenAddress = await clearingHouseTest.getTruncatedTokenAddress(settlementToken.address);
      await clearingHouseTest
        .connect(user2)
        .updateMargin(user2AccountNo, truncatedSettlementTokenAddress, parseTokenAmount(10 ** 6, 6));

      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const { sqrtPriceX96 } = await vPool.slot0();

      let tick = sqrtPriceX96ToTick(sqrtPriceX96);
      tick = tick - (tick % 10);

      const liquidityChangeParams = {
        tickLower: tick - 100,
        tickUpper: tick + 100,
        liquidityDelta: 10n ** 19n,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };

      await clearingHouseTest.connect(user2).updateRangeOrder(user2AccountNo, truncatedAddress, liquidityChangeParams);

      const netPosition = await clearingHouseTest.getAccountNetTokenPosition(user2AccountNo, truncatedAddress);
      expect(netPosition).to.eq(-1); // there is a delta of 1 wei due to rounding up and down
    });
  });
  describe('#SwapTokenAmout - Without Limit', () => {
    after(async () => {
      await closeTokenPosition(user1, user1AccountNo, vTokenAddress);
      await clearingHouseTest.cleanPositions(user1AccountNo);
    });
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vQuoteAddress);
      const swapParams = {
        amount: parseTokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user2).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      const swapParams = {
        amount: parseTokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('PoolDoesNotExist(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress1);
      const swapParams = {
        amount: parseTokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('PoolNotAllowedForTrade(' + +truncate(vTokenAddress1) + ')');
    });
    it('Fail - Low Notional Value', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const swapParams = {
        amount: parseTokenAmount('1', 8),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      expect(clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams)).to.be.reverted;
    });
    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const swapParams = {
        amount: parseTokenAmount('1', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
      const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vTokenAddress);
      expect(accountTokenPosition.balance).to.eq(parseTokenAmount('1', 18));
      expect(accountTokenPosition.netTraderPosition).to.eq(parseTokenAmount('1', 18));
    });
  });
  describe('#SwapTokenNotional - Without Limit', () => {
    after(async () => {
      await closeTokenPosition(user1, user1AccountNo, vTokenAddress);
      await clearingHouseTest.cleanPositions(user1AccountNo);
    });
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vQuoteAddress);
      const swapParams = {
        amount: parseTokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };

      await expect(
        clearingHouseTest.connect(user2).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      const swapParams = {
        amount: parseTokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };

      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('PoolDoesNotExist(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress1);
      const swapParams = {
        amount: parseTokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('PoolNotAllowedForTrade(' + +truncate(vTokenAddress1) + ')');
    });
    it('Fail - Low Notional Value', async () => {
      const curSqrtPrice = await oracle.getTwapSqrtPriceX96(0);
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const amount = parseTokenAmount('1', 6).div(100).sub(1);
      const swapParams = {
        amount: amount,
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('LowNotionalValue(' + amount + ')');
    });

    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const amount = parseTokenAmount('1', 6).div(10);
      const swapParams = {
        amount: amount,
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
      const accountTokenPosition = await clearingHouseTest.functions.getAccountQuoteBalance(user1AccountNo);
      expect(accountTokenPosition.balance).to.eq(amount.mul(-1));
    });
  });
  describe('#LiquidityChange - Without Limit', () => {
    let tickLower: BigNumberish;
    let tickUpper: BigNumberish;
    before(async () => {
      const { sqrtPriceX96 } = await vPool.slot0();

      let tick = sqrtPriceX96ToTick(sqrtPriceX96);
      tick = tick - (tick % 10);

      tickLower = tick - 100;
      tickUpper = tick + 100;
    });
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vQuoteAddress);
      const liquidityChangeParams = {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      await expect(
        clearingHouseTest.connect(user2).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      const liquidityChangeParams = {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      await expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('PoolDoesNotExist(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress1);
      const liquidityChangeParams = {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      await expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('PoolNotAllowedForTrade(' + +truncate(vTokenAddress1) + ')');
    });

    it('Fail - Low Notional Value', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const liquidityChangeParams = {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: 10n ** 6n,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };

      expect(clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams))
        .to.be.reverted;
    });

    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const liquidityChangeParams = {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: 10n ** 15n,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      await clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(
        vTokenAddress,
        0,
        liquidityChangeParams.tickLower,
        liquidityChangeParams.tickUpper,
        liquidityChangeParams.limitOrderType,
        liquidityChangeParams.liquidityDelta,
      );
    });
  });

  describe('Multicall', () => {
    it('multicallWithSingleMarginCheck', async () => {
      await settlementToken.connect(user1).approve(clearingHouseTest.address, parseUnits('1000', 6));

      const operations: Array<IClearingHouseStructures.MulticallOperationStruct> = [
        {
          operationType: 0,
          data: ethers.utils.defaultAbiCoder.encode(
            ['uint32', 'int256'],
            [truncate(settlementToken.address), parseUnits('100', 6)],
          ),
        },
        {
          operationType: 0,
          data: ethers.utils.defaultAbiCoder.encode(
            ['uint32', 'int256'],
            [truncate(settlementToken.address), parseUnits('-10', 6)],
          ),
        },
        // {
        //   operationType: 1,
        //   data: ethers.utils.defaultAbiCoder.encode(
        //     ['uint256'],
        //     [parseUnits('10', 6)],
        //   ),
        // },
        {
          operationType: 2,
          data: ethers.utils.defaultAbiCoder.encode(
            [
              'tuple(uint32 vTokenTruncatedAddress, tuple(int256 amount, uint160 sqrtPriceLimit, bool isNotional, bool isPartialAllowed) swapParams)',
            ],
            [
              {
                vTokenTruncatedAddress: truncate(vTokenAddress),
                swapParams: {
                  amount: parseUnits('1', 6),
                  sqrtPriceLimit: 0,
                  isNotional: true,
                  isPartialAllowed: false,
                },
              },
            ],
          ),
        },
        {
          operationType: 2,
          data: ethers.utils.defaultAbiCoder.encode(
            [
              'tuple(uint32 vTokenTruncatedAddress, tuple(int256 amount, uint160 sqrtPriceLimit, bool isNotional, bool isPartialAllowed) swapParams)',
            ],
            [
              {
                vTokenTruncatedAddress: truncate(vTokenAddress),
                swapParams: {
                  amount: parseUnits('-2', 6),
                  sqrtPriceLimit: 0,
                  isNotional: true,
                  isPartialAllowed: false,
                },
              },
            ],
          ),
        },
      ];
      await clearingHouseTest.connect(user1).multicallWithSingleMarginCheck(user1AccountNo, operations);
    });
  });

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

  async function getCollateralSettings(vTokenAddress: string) {
    let {
      token,
      settings: { oracle, twapDuration, isAllowedForDeposit },
    } = await clearingHouseTest.getCollateralInfo(truncate(vTokenAddress));
    return { token, settings: { oracle, twapDuration, isAllowedForDeposit } };
  }

  async function getPoolsSumA(poolIds: string[]) {
    return await Promise.all(
      poolIds.map(async poolId => {
        const { vPoolWrapper } = await clearingHouseTest.getPoolInfo(poolId);
        const wrapper = await hre.ethers.getContractAt('VPoolWrapper', vPoolWrapper);
        return await wrapper.getSumAX128();
      }),
    );
  }
});
