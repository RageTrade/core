import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
import { AccountTest, VPoolFactory, ClearingHouse, ERC20, RealTokenMock } from '../typechain-types';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { tokenAmount } from './utils/stealFunds';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { smock } from '@defi-wonderland/smock';
config();
const { ALCHEMY_KEY } = process.env;

describe('AccountTest Library', () => {
  let test: AccountTest;

  let vTokenAddress: string;
  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;
  let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

  async function checkTokenBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const vTokenPosition = await test.getAccountTokenDetails(vTokenAddress);
    expect(vTokenPosition.balance).to.eq(vTokenBalance);
  }

  async function checkDepositBalance(vTokenAddress: string, vTokenBalance: BigNumberish) {
    const balance = await test.getAccountDepositBalance(vTokenAddress);
    expect(balance).to.eq(vTokenBalance);
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

  async function initializePool(
    VPoolFactory: VPoolFactory,
    initialMargin: BigNumberish,
    maintainanceMargin: BigNumberish,
    twapDuration: BigNumberish,
  ) {
    await VPoolFactory.initializePool(
      'vWETH',
      'vWETH',
      realToken.address,
      oracleAddress,
      500,
      500,
      initialMargin,
      maintainanceMargin,
      twapDuration,
    );

    const eventFilter = VPoolFactory.filters.PoolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    // console.log('VBASE ADDRESS: ', vBaseAddress);
    // console.log('Wrapper Address: ', vPoolWrapper);
    // console.log('Clearing House Address: ', clearingHouse.address);
    // console.log('Oracle Address: ', oracleAddress);
  }

  before(async () => {
    await activateMainnetFork();

    const rBase = await smock.fake<ERC20>('ERC20');
    rBase.decimals.returns(18);
    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    const vBase = await vBaseFactory.deploy(rBase.address);
    vBaseAddress = vBase.address;

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    oracleAddress = oracle.address;
    signers = await hre.ethers.getSigners();

    const futureVPoolFactoryAddress = await getCreateAddressFor(signers[0], 2);
    const futureInsurnaceFundAddress = await getCreateAddressFor(signers[0], 3);

    const VPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);

    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(futureVPoolFactoryAddress, REAL_BASE, futureInsurnaceFundAddress);

    const VPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      vBaseAddress,
      clearingHouse.address,
      VPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );

    const InsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(rBase.address, clearingHouse.address);

    await vBase.transferOwnership(VPoolFactory.address);
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    realToken = await realTokenFactory.deploy();

    await initializePool(VPoolFactory, 20, 10, 1);
    const factory = await hre.ethers.getContractFactory('AccountTest');
    test = await factory.deploy();

    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;

    constants = await VPoolFactory.constants();
  });

  after(async () => {
    await deactivateMainnetFork();
  });

  describe('#Initialize', () => {
    it('Init', async () => {
      test.initToken(vTokenAddress);
    });

    it('Mint', async () => {
      await realToken.mint(ownerAddress, '10000000000');
      await realToken.approve(testContractAddress, '1000000000');
    });
  });

  describe('#Margin', () => {
    it('Add Margin', async () => {
      await test.addMargin(vBaseAddress, '10000000000', constants);
      await checkDepositBalance(vBaseAddress, '10000000000');
    });

    it('Remove Margin', async () => {
      await test.removeMargin(vBaseAddress, '50', constants);
      await checkDepositBalance(vBaseAddress, '9999999950');
    });
  });

  describe('#Trades', () => {
    it('Swap Token (Token Amount)', async () => {
      await test.swapTokenAmount(vTokenAddress, '10', constants);
      await checkTokenBalance(vTokenAddress, '10');
      await checkTokenBalance(vBaseAddress, -40000);
    });

    it('Swap Token (Token Notional)', async () => {
      await test.swapTokenNotional(vTokenAddress, '40000', constants);
      await checkTokenBalance(vTokenAddress, '20');
      await checkTokenBalance(vBaseAddress, -80000);
    });

    it('Liqudity Change', async () => {
      await test.cleanPositions(constants);
      await test.liquidityChange(vTokenAddress, -100, 100, 5, 0, constants);
      await checkTokenBalance(vTokenAddress, '-5');
      await checkTokenBalance(vBaseAddress, -20000);
      await checkLiquidityPositionNum(vTokenAddress, 1);
      await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 0, 5);
    });
  });

  describe('#Remove Limit Order', () => {
    describe('Not limit order', () => {
      before(async () => {
        await test.cleanPositions(constants);
        await test.liquidityChange(vTokenAddress, -100, 100, 5, 0, constants);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 0, 5);
      });
      it('Remove Failure - Inside Range (No Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, 90, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Below Range (No Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, -110, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Above Range (No Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, 110, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
    });
    describe('Lower limit order', () => {
      before(async () => {
        await test.cleanPositions(constants);
        await test.liquidityChange(vTokenAddress, -100, 100, 5, 1, constants);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 1, 5);
      });
      it('Remove Failure - Inside Range (Lower Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, 90, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Above Range (Lower Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, 110, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Success - Below Range (Lower Limit)', async () => {
        test.removeLimitOrder(vTokenAddress, -100, 100, -110, constants);
        await checkTokenBalance(vTokenAddress, 0);
        await checkTokenBalance(vBaseAddress, 0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
    describe('Upper limit order', () => {
      before(async () => {
        await test.cleanPositions(constants);
        await test.liquidityChange(vTokenAddress, -100, 100, 5, 2, constants);
        await checkTokenBalance(vTokenAddress, '-5');
        await checkTokenBalance(vBaseAddress, -20000);
        await checkLiquidityPositionNum(vTokenAddress, 1);
        await checkLiquidityPositionDetails(vTokenAddress, 0, -100, 100, 2, 5);
      });
      it('Remove Failure - Inside Range (Upper Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, 90, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Failure - Below Range (Upper Limit)', async () => {
        expect(test.removeLimitOrder(vTokenAddress, -100, 100, -110, constants)).to.be.revertedWith(
          'IneligibleLimitOrderRemoval()',
        );
      });
      it('Remove Success - Above Range (Upper Limit)', async () => {
        test.removeLimitOrder(vTokenAddress, -100, 100, 110, constants);
        await checkTokenBalance(vTokenAddress, 0);
        await checkTokenBalance(vBaseAddress, 0);
        await checkLiquidityPositionNum(vTokenAddress, 0);
      });
    });
  });

  describe('#Liquidation', () => {
    it('Liquidate Liquidity Positions - Fail', async () => {
      expect(test.liquidateLiquidityPositions(tokenAmount(10, 6), 150, 5000, constants)).to.be.reverted; // feeFraction=15/10=1.5
    });
    it('Liquidate Token Positions - Fail', async () => {
      expect(test.liquidateTokenPosition(vTokenAddress, tokenAmount(10, 6), 5000, 150, 5000, constants)).to.be.reverted;
    });
  });
});
