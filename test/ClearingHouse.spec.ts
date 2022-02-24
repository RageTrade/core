import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ethers } from 'ethers';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
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
} from '../typechain-types';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './utils/realConstants';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { stealFunds, tokenAmount } from './utils/stealFunds';
import { priceToSqrtPriceX96, sqrtPriceX96ToTick } from './utils/price-tick';

import { smock } from '@defi-wonderland/smock';
import { ADDRESS_ZERO } from '@uniswap/v3-sdk';
import { randomAddress } from './utils/random';
import { MulticallOperationStruct } from '../typechain-types/ClearingHouse';
import { truncate } from './utils/vToken';
import { parseUnits } from '@ethersproject/units';
const whaleForBase = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

config();
const { ALCHEMY_KEY } = process.env;

describe('Clearing House Library', () => {
  let test: AccountTest;

  let vBaseAddress: string;
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

  let rBase: IERC20;
  let rBaseOracle: OracleMock;

  let rBase1: IERC20;
  let rBase1Oracle: OracleMock;

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
    initialMarginRatio: BigNumberish,
    maintainanceMarginRatio: BigNumberish,
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
      rageTradePoolInitialSettings: {
        initialMarginRatio,
        maintainanceMarginRatio,
        twapDuration,
        supported: false,
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

    rBase = await hre.ethers.getContractAt('IERC20', REAL_BASE);

    // const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    // const vBase = await vBaseFactory.deploy(REAL_BASE);
    // vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user1 = signers[1];
    user2 = signers[2];

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

    const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

    const insuranceFundLogic = await (await hre.ethers.getContractFactory('InsuranceFund')).deploy();

    const nativeOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    const rageTradeFactory = await (
      await hre.ethers.getContractFactory('RageTradeFactory')
    ).deploy(
      clearingHouseTestLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      rBase.address,
      nativeOracle.address,
    );

    clearingHouseTest = await hre.ethers.getContractAt('ClearingHouseTest', await rageTradeFactory.clearingHouse());

    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouseTest.insuranceFund());
    hre.tracer.nameTags[insuranceFund.address] = 'insuranceFund';

    const vBase = await hre.ethers.getContractAt('VBase', await rageTradeFactory.vBase());
    vBaseAddress = vBase.address;

    // await vBase.transferOwnership(VPoolFactory.address);
    // const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    // realToken = await realTokenFactory.deploy();

    let out = await initializePool(
      rageTradeFactory,
      20_000,
      10_000,
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
      20_000,
      10_000,
      1,
      await priceToSqrtPriceX96(4000, 6, 18),
      // .div(60 * 10 ** 6),
    );
    vTokenAddress1 = out1.vTokenAddress;

    // console.log('### Is VToken 0 ? ###');
    // console.log(BigNumber.from(vTokenAddress).lt(vBaseAddress));
    // console.log(vTokenAddress);
    // console.log(vBaseAddress);
    // console.log('### Base decimals ###');
    // console.log(await vBase.decimals());

    // constants = await VPoolFactory.constants();
    rBaseOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    rBase1 = await hre.ethers.getContractAt('IERC20', '0x6B175474E89094C44Da98b954EedeAC495271d0F');
    rBase1Oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
    await clearingHouseTest.updateCollateralSettings(rBase.address, {
      oracle: rBaseOracle.address,
      twapDuration: 300,
      supported: false,
    });

    await clearingHouseTest.updateCollateralSettings(rBase1.address, {
      oracle: rBase1Oracle.address,
      twapDuration: 300,
      supported: false,
    });
  });

  after(deactivateMainnetFork);

  describe('#Init Params', () => {
    it('Set Params', async () => {
      const liquidationParams = {
        liquidationFeeFraction: 1500,
        tokenLiquidationPriceDeltaBps: 3000,
        insuranceFundFeeShareBps: 5000,
      };
      const fixFee = tokenAmount(10, 6);
      const removeLimitOrderFee = tokenAmount(10, 6);
      const minimumOrderNotional = tokenAmount(1, 6).div(100);
      const minRequiredMargin = tokenAmount(20, 6);

      await clearingHouseTest.updateProtocolSettings(
        liquidationParams,
        removeLimitOrderFee,
        minimumOrderNotional,
        minRequiredMargin,
      );
      await clearingHouseTest.setFixFee(fixFee);
      const protocol = await clearingHouseTest.protocolInfo();
      const curPaused = await clearingHouseTest.paused();

      expect(await clearingHouseTest.fixFee()).eq(fixFee);
      expect(protocol.minRequiredMargin).eq(minRequiredMargin);
      expect(protocol.liquidationParams.liquidationFeeFraction).eq(liquidationParams.liquidationFeeFraction);
      expect(protocol.liquidationParams.tokenLiquidationPriceDeltaBps).eq(
        liquidationParams.tokenLiquidationPriceDeltaBps,
      );
      expect(protocol.liquidationParams.insuranceFundFeeShareBps).eq(liquidationParams.insuranceFundFeeShareBps);

      expect(protocol.removeLimitOrderFee).eq(removeLimitOrderFee);
      expect(protocol.minimumOrderNotional).eq(minimumOrderNotional);
      expect(curPaused).to.be.false;
    });
  });

  describe('#StealFunds', () => {
    it('Steal Funds', async () => {
      await stealFunds(REAL_BASE, 6, user1.address, '1000000', whaleForBase);
      await stealFunds(rBase1.address, 6, user1.address, '1000000', whaleForBase);
      await stealFunds(REAL_BASE, 6, user2.address, 10 ** 6, whaleForBase);
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('1000000', 6));
      expect(await rBase.balanceOf(user2.address)).to.eq(tokenAmount(10 ** 6, 6));
    });
  });

  describe('#AccountCreation', () => {
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user1).createAccount();
      user1AccountNo = 0;
      expect(await clearingHouseTest.numAccounts()).to.eq(1);
      expect(await clearingHouseTest.getAccountOwner(user1AccountNo)).to.eq(user1.address);
      expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user1AccountNo)).to.eq(user1AccountNo);
    });
    it('Create Account - 1', async () => {
      await clearingHouseTest.connect(user2).createAccount();
      user2AccountNo = 1;
      expect(await clearingHouseTest.numAccounts()).to.eq(2);
      expect(await clearingHouseTest.getAccountOwner(user2AccountNo)).to.eq(user2.address);
      expect(await clearingHouseTest.getAccountNumInTokenPositionSet(user2AccountNo)).to.eq(user2AccountNo);
    });
  });

  describe('#InitializeToken', () => {
    it('vToken Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokens(vTokenAddress)).to.eq(vTokenAddress);
    });
    // it('vBase Intialized', async () => {
    //   expect(await clearingHouseTest.getTokenAddressInVTokens(vBaseAddress)).to.eq(vBaseAddress);
    // });
    it('Other Address Not Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokens(dummyTokenAddress)).to.eq(ADDRESS_ZERO);
    });
  });

  describe('#TokenSupport', () => {
    before(async () => {
      expect((await clearingHouseTest.pools(vTokenAddress)).settings.supported).to.be.false;
      expect((await clearingHouseTest.cTokens(truncate(realToken.address))).settings.supported).to.be.false;
      expect((await clearingHouseTest.pools(vBaseAddress)).settings.supported).to.be.false;
      expect((await clearingHouseTest.cTokens(truncate(rBase.address))).settings.supported).to.be.false;
      // expect(await clearingHouseTest.supportedVTokens(vBaseAddress)).to.be.false;
      // expect(await clearingHouseTest.supportedDeposits(rBase.address)).to.be.false;
    });
    it('Add Token Position Support - Fail - Unauthorized', async () => {
      const settings = await getPoolSettings(vTokenAddress);
      settings.supported = true;
      await expect(clearingHouseTest.connect(user1).updatePoolSettings(vTokenAddress, settings)).to.be.revertedWith(
        'Unauthorised()',
      );
    });
    it('Add Token Position Support - Pass', async () => {
      const settings = await getPoolSettings(vTokenAddress);
      settings.supported = true;
      await clearingHouseTest.connect(admin).updatePoolSettings(vTokenAddress, settings);
      expect((await clearingHouseTest.pools(vTokenAddress)).settings.supported).to.be.true;
    });
    it('Add Token Deposit Support - Fail - Unauthorized', async () => {
      const { settings } = await getCollateralSettings(realToken.address);
      settings.supported = true;
      await expect(
        clearingHouseTest.connect(user1).updateCollateralSettings(realToken.address, settings),
      ).to.be.revertedWith('Unauthorised()');
    });
    // it('Add Token Deposit Support - Uninitialized Collateral', async () => {
    //   await expect(clearingHouseTest.connect(admin).updateSupportedDeposits(vTokenAddress, true)).to.be.revertedWith(
    //     'Invalid Address',
    //   );
    // });
    it('Add Base Deposit Support  - Pass', async () => {
      const { settings } = await getCollateralSettings(rBase.address);
      settings.supported = true;
      await clearingHouseTest.connect(admin).updateCollateralSettings(rBase.address, settings);
      expect((await getCollateralSettings(rBase.address)).settings.supported).to.be.true;
    });
  });

  describe('#Pause Check', () => {
    let amount: BigNumberish;
    let truncatedAddress: number;
    let swapParams: any;
    let liquidityChangeParams: any;

    before(async () => {
      amount = tokenAmount('1000000', 6);
      truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      swapParams = {
        amount: tokenAmount('10000', 18),
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
    });
    it('Pause', async () => {
      await clearingHouseTest.setPaused(true);
      const curPaused = await clearingHouseTest.paused();

      expect(curPaused).to.be.true;
    });

    it('Create Account', async () => {
      await expect(clearingHouseTest.createAccount()).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('Deposit', async () => {
      expect(clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, amount)).to.be.revertedWith(
        'Paused()',
      );
      await clearingHouseTest.paused();
    });

    it('Withdraw', async () => {
      await expect(
        clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, amount),
      ).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('Profit', async () => {
      await expect(clearingHouseTest.connect(user1).updateProfit(user1AccountNo, amount)).to.be.revertedWith(
        'Paused()',
      );
      await clearingHouseTest.paused();
    });

    it('Token Position', async () => {
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('Range Position', async () => {
      await expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('Token Liquidation', async () => {
      await expect(
        clearingHouseTest.connect(user2).liquidateTokenPosition(user2AccountNo, user1AccountNo, truncatedAddress, 5000),
      ).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('Range Liquidation', async () => {
      await expect(clearingHouseTest.connect(user2).liquidateLiquidityPositions(user1AccountNo)).to.be.revertedWith(
        'Paused()',
      );
      await clearingHouseTest.paused();
    });

    it('Remove Limit Order', async () => {
      await expect(
        clearingHouseTest.connect(user2).removeLimitOrder(user1AccountNo, truncatedAddress, -100, 100),
      ).to.be.revertedWith('Paused()');
      await clearingHouseTest.paused();
    });

    it('UnPause', async () => {
      await clearingHouseTest.setPaused(false);
      const curPaused = await clearingHouseTest.paused();

      expect(curPaused).to.be.false;
    });
  });

  describe('#Deposit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      await expect(
        clearingHouseTest.connect(user2).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      await expect(
        clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase1.address);
      await expect(
        clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UnsupportedCToken("' + rBase1.address + '")');
    });
    it('Pass', async () => {
      await rBase.connect(user1).approve(clearingHouseTest.address, tokenAmount('1000000', 6));
      const truncatedRBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      await clearingHouseTest
        .connect(user1)
        .addMargin(user1AccountNo, truncatedRBaseAddress, tokenAmount('1000000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('0', 6));
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('1000000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, rBase.address)).to.eq(
        tokenAmount('1000000', 6),
      );
    });
  });
  describe('#Withdraw', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      await expect(
        clearingHouseTest.connect(user2).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      await expect(
        clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });

    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      await clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('100000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('100000', 6));
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('900000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, rBase.address)).to.eq(
        tokenAmount('900000', 6),
      );
    });

    it('Pass - Withdrawal after removal of token support', async () => {
      //Add rBase1 support
      const { settings } = await getCollateralSettings(rBase1.address);
      settings.supported = true;
      await clearingHouseTest.connect(admin).updateCollateralSettings(rBase1.address, settings);
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase1.address);

      await rBase1.connect(user1).approve(clearingHouseTest.address, tokenAmount('1000000', 6));
      await clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6));
      expect(await rBase1.balanceOf(user1.address)).to.eq(0);
      expect(await rBase1.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('1000000', 6));

      //Remove rBase1 support
      settings.supported = false;
      await clearingHouseTest.connect(admin).updateCollateralSettings(rBase1.address, settings);

      await clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6));

      expect(await rBase1.balanceOf(user1.address)).to.eq(tokenAmount('1000000', 6));
      expect(await rBase1.balanceOf(clearingHouseTest.address)).to.eq(0);
    });
  });

  describe('#Profit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      await expect(
        clearingHouseTest.connect(user2).updateProfit(user1AccountNo, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });

    it('Pass - Cover Loss', async () => {
      await rBase.connect(user1).approve(clearingHouseTest.address, tokenAmount('100000', 6));
      await clearingHouseTest.connect(user1).updateProfit(user1AccountNo, tokenAmount('100000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(0);
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('1000000', 6));
      const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vBaseAddress);
      expect(accountTokenPosition.balance).to.eq(tokenAmount('100000', 6));
    });

    it('Pass - Remove Profit', async () => {
      await clearingHouseTest.connect(user1).updateProfit(user1AccountNo, -tokenAmount('100000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('100000', 6));
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('900000', 6));
      const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vBaseAddress);
      expect(accountTokenPosition.balance).to.eq(0);
    });
  });
  describe('#InitLiquidity', async () => {
    it('#InitLiquidity', async () => {
      await rBase.connect(user2).approve(clearingHouseTest.address, tokenAmount(10 ** 6, 6));
      const truncatedRBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(rBase.address);
      await clearingHouseTest.connect(user2).addMargin(user2AccountNo, truncatedRBaseAddress, tokenAmount(10 ** 6, 6));

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
    });
  });
  describe('#SwapTokenAmout - Without Limit', () => {
    after(async () => {
      await closeTokenPosition(user1, user1AccountNo, vTokenAddress);
      await clearingHouseTest.cleanPositions(user1AccountNo);
    });
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 18),
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
        amount: tokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress1);
      const swapParams = {
        amount: tokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UnsupportedVToken("' + vTokenAddress1 + '")');
    });
    it('Fail - Low Notional Value', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const swapParams = {
        amount: tokenAmount('1', 8),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      expect(clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams)).to.be.reverted;
    });
    it('Pass', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const swapParams = {
        amount: tokenAmount('1', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
      const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vTokenAddress);
      expect(accountTokenPosition.balance).to.eq(tokenAmount('1', 18));
      expect(accountTokenPosition.netTraderPosition).to.eq(tokenAmount('1', 18));
    });
  });
  describe('#SwapTokenNotional - Without Limit', () => {
    after(async () => {
      await closeTokenPosition(user1, user1AccountNo, vTokenAddress);
      await clearingHouseTest.cleanPositions(user1AccountNo);
    });
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 6),
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
        amount: tokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };

      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress1);
      const swapParams = {
        amount: tokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      await expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UnsupportedVToken("' + vTokenAddress1 + '")');
    });
    it('Fail - Low Notional Value', async () => {
      const curSqrtPrice = await oracle.getTwapSqrtPriceX96(0);
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const amount = tokenAmount('1', 6).div(100).sub(1);
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
      const amount = tokenAmount('1', 6).div(10);
      const swapParams = {
        amount: amount,
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
      const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vBaseAddress);
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
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
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
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
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
      ).to.be.revertedWith('UnsupportedVToken("' + vTokenAddress1 + '")');
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
      await rBase.connect(user1).approve(clearingHouseTest.address, parseUnits('1000', 6));

      const operations: Array<MulticallOperationStruct> = [
        {
          operationType: 0,
          data: ethers.utils.defaultAbiCoder.encode(
            ['uint32', 'uint256'],
            [truncate(rBase.address), parseUnits('100', 6)],
          ),
        },
        {
          operationType: 1,
          data: ethers.utils.defaultAbiCoder.encode(
            ['uint32', 'uint256'],
            [truncate(rBase.address), parseUnits('10', 6)],
          ),
        },
        // {
        //   operationType: 2,
        //   data: ethers.utils.defaultAbiCoder.encode(
        //     ['uint256'],
        //     [parseUnits('10', 6)],
        //   ),
        // },
        {
          operationType: 3,
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
          operationType: 3,
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
      settings: { initialMarginRatio, maintainanceMarginRatio, twapDuration, supported, isCrossMargined, oracle },
    } = await clearingHouseTest.pools(vTokenAddress);
    return { initialMarginRatio, maintainanceMarginRatio, twapDuration, supported, isCrossMargined, oracle };
  }

  async function getCollateralSettings(vTokenAddress: string) {
    let {
      token,
      settings: { oracle, twapDuration, supported },
    } = await clearingHouseTest.cTokens(truncate(vTokenAddress));
    return { token, settings: { oracle, twapDuration, supported } };
  }
});
