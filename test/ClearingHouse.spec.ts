import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ethers } from 'ethers';

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
} from '../typechain-types';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { stealFunds, tokenAmount } from './utils/stealFunds';
import { sqrtPriceX96ToTick } from './utils/price-tick';

import { smock } from '@defi-wonderland/smock';
import { ADDRESS_ZERO } from '@uniswap/v3-sdk';
const whaleForBase = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

config();
const { ALCHEMY_KEY } = process.env;

describe('Clearing House Library', () => {
  let test: AccountTest;

  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let constants: ConstantsStruct;
  let clearingHouseTest: ClearingHouseTest;
  let vPool: IUniswapV3Pool;

  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user1AccountNo: BigNumberish;
  let user2AccountNo: BigNumberish;

  let rBase: IERC20;

  let vTokenAddress: string;
  let vTokenAddress1: string;
  let dummyTokenAddress: string;

  let oracle: OracleMock;
  let oracle1: OracleMock;

  let realToken: RealTokenMock;
  let realToken1: RealTokenMock;

  async function initializePool(
    VPoolFactory: VPoolFactory,
    initialMargin: BigNumberish,
    maintainanceMargin: BigNumberish,
    twapDuration: BigNumberish,
    initialPrice: BigNumberish,
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    oracle.setSqrtPrice(initialPrice);

    await VPoolFactory.initializePool(
      'vWETH',
      'vWETH',
      realToken.address,
      oracle.address,
      500,
      500,
      initialMargin,
      maintainanceMargin,
      twapDuration,
      false,
    );

    const eventFilter = VPoolFactory.filters.PoolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    return { vTokenAddress, realToken, oracle, vPool };
  }

  before(async () => {
    await activateMainnetFork();

    dummyTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(148392483294).toHexString(), 20);

    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    const vBase = await vBaseFactory.deploy(REAL_BASE);
    vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user1 = signers[1];
    user2 = signers[2];

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
      20_000,
      10_000,
      1,
      BigNumber.from(1).mul(BigNumber.from(2).pow(96)),
      // .div(60 * 10 ** 6),
    );
    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;
    vPool = await hre.ethers.getContractAt('IUniswapV3Pool', out.vPool);

    constants = await VPoolFactory.constants();

    rBase = await hre.ethers.getContractAt('IERC20', REAL_BASE);
  });

  after(deactivateMainnetFork);

  describe('#StealFunds', () => {
    it('Steal Funds', async () => {
      await stealFunds(REAL_BASE, 6, user1.address, '1000000', whaleForBase);
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
      expect(await clearingHouseTest.getTokenAddressInVTokenAddresses(vTokenAddress)).to.eq(vTokenAddress);
    });
    it('vBase Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokenAddresses(vBaseAddress)).to.eq(vBaseAddress);
    });
    it('Other Address Not Intialized', async () => {
      expect(await clearingHouseTest.getTokenAddressInVTokenAddresses(dummyTokenAddress)).to.eq(ADDRESS_ZERO);
    });
  });

  describe('#TokenSupport', () => {
    before(async () => {
      expect(await clearingHouseTest.supportedVTokens(vTokenAddress)).to.be.false;
      expect(await clearingHouseTest.supportedDeposits(vTokenAddress)).to.be.false;
      expect(await clearingHouseTest.supportedVTokens(vBaseAddress)).to.be.false;
      expect(await clearingHouseTest.supportedDeposits(vBaseAddress)).to.be.false;
    });
    it('Add Token Position Support - Fail - Unauthorized', async () => {
      expect(clearingHouseTest.connect(user1).updateSupportedVTokens(vTokenAddress, true)).to.be.revertedWith(
        'Unauthorised()',
      );
    });
    it('Add Token Position Support - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedVTokens(vTokenAddress, true);
      expect(await clearingHouseTest.supportedVTokens(vTokenAddress)).to.be.true;
    });
    it('Add Token Deposit Support - Fail - Unauthorized', async () => {
      expect(clearingHouseTest.connect(user1).updateSupportedDeposits(vTokenAddress, true)).to.be.revertedWith(
        'Unauthorised()',
      );
    });
    it('Add Token Deposit Support  - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedDeposits(vTokenAddress, true);
      expect(await clearingHouseTest.supportedDeposits(vTokenAddress)).to.be.true;
    });
    it('Remove Token Deposit Support  - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedDeposits(vTokenAddress, false);
      expect(await clearingHouseTest.supportedDeposits(vTokenAddress)).to.be.false;
    });
    it('Add Base Deposit Support  - Pass', async () => {
      await clearingHouseTest.connect(admin).updateSupportedDeposits(vBaseAddress, true);
      expect(await clearingHouseTest.supportedDeposits(vBaseAddress)).to.be.true;
    });
  });

  describe('#Deposit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      expect(
        clearingHouseTest.connect(user2).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      expect(
        clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      expect(
        clearingHouseTest.connect(user1).addMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UnsupportedToken("' + vTokenAddress + '")');
    });
    it('Pass', async () => {
      await rBase.connect(user1).approve(clearingHouseTest.address, tokenAmount('1000000', 6));
      const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      await clearingHouseTest
        .connect(user1)
        .addMargin(user1AccountNo, truncatedVBaseAddress, tokenAmount('1000000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('0', 6));
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('1000000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, vBaseAddress)).to.eq(
        tokenAmount('1000000', 6),
      );
    });
  });
  describe('#Withdraw', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      expect(
        clearingHouseTest.connect(user2).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      expect(
        clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      expect(
        clearingHouseTest.connect(user1).removeMargin(user1AccountNo, truncatedAddress, tokenAmount('1000000', 6)),
      ).to.be.revertedWith('UnsupportedToken("' + vTokenAddress + '")');
    });
    it('Pass', async () => {
      const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      await clearingHouseTest
        .connect(user1)
        .removeMargin(user1AccountNo, truncatedVBaseAddress, tokenAmount('100000', 6));
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('100000', 6));
      expect(await rBase.balanceOf(clearingHouseTest.address)).to.eq(tokenAmount('900000', 6));
      expect(await clearingHouseTest.getAccountDepositBalance(user1AccountNo, vBaseAddress)).to.eq(
        tokenAmount('900000', 6),
      );
    });
  });
  describe('#InitLiquidity', async () => {
    it('#InitLiquidity', async () => {
      await rBase.connect(user2).approve(clearingHouseTest.address, tokenAmount(10 ** 6, 6));
      const truncatedVBaseAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      await clearingHouseTest.connect(user2).addMargin(user2AccountNo, truncatedVBaseAddress, tokenAmount(10 ** 6, 6));

      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
      const { sqrtPriceX96 } = await vPool.slot0();

      const tick = sqrtPriceX96ToTick(sqrtPriceX96);

      const liquidityChangeParams = {
        tickLower: tick - 100,
        tickUpper: tick + 100,
        liquidityDelta: 10 ** 5,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      console.log('Account Owner');
      console.log(await clearingHouseTest.getAccountOwner(user2AccountNo));
      await clearingHouseTest.connect(user2).updateRangeOrder(user2AccountNo, truncatedAddress, liquidityChangeParams);
    });
  });
  describe('#SwapTokenAmout - Without Limit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      expect(
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
      expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 18),
        sqrtPriceLimit: 0,
        isNotional: false,
        isPartialAllowed: false,
      };
      expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UnsupportedToken("' + vBaseAddress + '")');
    });
    it('Fail - Low Notional Value');
    it('Pass');
    // , async () => {
    //   const curSqrtPrice = await oracle.getTwapSqrtPriceX96(0);
    //   const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
    //   const swapParams = {
    //     amount: tokenAmount('1', 16),
    //     sqrtPriceLimit: curSqrtPrice.mul(101).div(100),
    //     isNotional: false,
    //   };
    //   await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
    //   const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vTokenAddress);
    //   console.log(accountTokenPosition);
    //   expect(accountTokenPosition.balance).to.eq(tokenAmount('10000', 18));
    //   expect(accountTokenPosition.netTraderPosition).to.eq(tokenAmount('10000', 18));
    // });
  });
  describe('#SwapTokenNotional - Without Limit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };

      expect(
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

      expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const swapParams = {
        amount: tokenAmount('10000', 6),
        sqrtPriceLimit: 0,
        isNotional: true,
        isPartialAllowed: false,
      };
      expect(
        clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams),
      ).to.be.revertedWith('UnsupportedToken("' + vBaseAddress + '")');
    });
    it('Fail - Low Notional Value');
    // , async() => {
    //   const curSqrtPrice = await oracle.getTwapSqrtPriceX96(0);
    //   const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
    //   const swapParams = {
    //     amount: tokenAmount('1', 6),
    //     sqrtPriceLimit: curSqrtPrice.mul(110).div(100),
    //     isNotional: true,
    //   };
    //   expect(clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams)).to.be.revertedWith("LowNotionalValue()");
    //   const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vTokenAddress);
    // });

    it('Pass');
    // , async () => {
    //   const curSqrtPrice = await oracle.getTwapSqrtPriceX96(0);
    //   const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
    //   const swapParams = {
    //     amount: tokenAmount('10000', 6),
    //     sqrtPriceLimit: curSqrtPrice.mul(110).div(100),
    //     isNotional: true,
    //   };
    //   await clearingHouseTest.connect(user1).swapToken(user1AccountNo, truncatedAddress, swapParams);
    //   const accountTokenPosition = await clearingHouseTest.getAccountOpenTokenPosition(user1AccountNo, vTokenAddress);
    //   console.log(accountTokenPosition);
    //   expect(accountTokenPosition.balance).to.eq(tokenAmount('10000', 18));
    //   expect(accountTokenPosition.netTraderPosition).to.eq(tokenAmount('10000', 18));
    // });
  });
  describe('#LiquidityChange - Without Limit', () => {
    it('Fail - Access Denied', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const liquidityChangeParams = {
        tickLower: -100,
        tickUpper: 100,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      expect(
        clearingHouseTest.connect(user2).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('AccessDenied("' + user2.address + '")');
    });
    it('Fail - Uninitialized Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(dummyTokenAddress);
      const liquidityChangeParams = {
        tickLower: -100,
        tickUpper: 100,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('UninitializedToken(' + truncatedAddress + ')');
    });
    it('Fail - Unsupported Token', async () => {
      const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vBaseAddress);
      const liquidityChangeParams = {
        tickLower: -100,
        tickUpper: 100,
        liquidityDelta: 100000,
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageToleranceBps: 0,
      };
      expect(
        clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams),
      ).to.be.revertedWith('UnsupportedToken("' + vBaseAddress + '")');
    });

    it('Fail - Low Notional Value');

    it('Pass');
    // , async () => {
    //   const truncatedAddress = await clearingHouseTest.getTruncatedTokenAddress(vTokenAddress);
    //   const liquidityChangeParams = {
    //     tickLower: -100,
    //     tickUpper: 100,
    //     liquidityDelta: 100 ** 15,
    //     closeTokenPosition: false,
    //     limitOrderType: 0,
    //     sqrtPriceCurrent: 0,
    //     slippageToleranceBps: 0,
    //   };
    //   await clearingHouseTest.connect(user1).updateRangeOrder(user1AccountNo, truncatedAddress, liquidityChangeParams);
    // });
  });
});
