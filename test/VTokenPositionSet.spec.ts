import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest, VPoolFactory, VBase, VPoolWrapper, ERC20 } from '../typechain-types';
import {
  UNISWAP_FACTORY_ADDRESS,
  DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './utils/realConstants';
import { config } from 'dotenv';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from './utils/create-addresses';
const realToken0 = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
const realToken1 = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';

describe('VTokenPositionSet Library', () => {
  // const vTokenAddress: string = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  // const vTokenAddress1: string = utils.hexZeroPad(BigNumber.from(2).toHexString(), 20);
  let VTokenPositionSet: VTokenPositionSetTest;
  let vTokenAddress: string;
  let vTokenAddress1: string;
  let VPoolFactory: VPoolFactory;
  let VBase: VBase;
  let VPoolWrapper: VPoolWrapper;
  let constants: ConstantsStruct;
  let signers: SignerWithAddress[];
  before(async () => {
    await activateMainnetFork();

    const realBase = await smock.fake<ERC20>('ERC20');
    realBase.decimals.returns(10);
    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy(realBase.address);
    const oracleAddress = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;

    signers = await hre.ethers.getSigners();
    const futureVPoolFactoryAddress = await getCreateAddressFor(signers[0], 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(signers[0], 4);

    const VPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy(futureVPoolFactoryAddress, REAL_BASE, futureInsurnaceFundAddress);
    VPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      VBase.address,
      clearingHouse.address,
      VPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      UNISWAP_V3_POOL_BYTE_CODE_HASH,
    );

    const InsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(realBase.address, clearingHouse.address);

    await VBase.transferOwnership(VPoolFactory.address);

    await VPoolFactory.initializePool(
      {
        setupVTokenParams: {
          vTokenName: 'vWETH',
          vTokenSymbol: 'vWETH',
          realTokenAddress: realToken0,
          oracleAddress: oracleAddress,
        },
        extendedLpFee: 500,
        protocolFee: 500,
        initialMarginRatio: 2,
        maintainanceMarginRatio: 3,
        twapDuration: 2,
        whitelisted: false,
      },
      0,
    );

    const eventFilter = VPoolFactory.filters.PoolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    vTokenAddress = events[0].args[1];
    // console.log('vTokenAddres', vTokenAddress);
    // console.log('VPoolFactoryAddress', VPoolFactory.address);
    // console.log('Vwrapper', events[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);
    await VPoolWrapper.liquidityChange(-10, 10, 10000000000000);

    await VPoolFactory.initializePool(
      {
        setupVTokenParams: {
          vTokenName: 'vWETH',
          vTokenSymbol: 'vWETH',
          realTokenAddress: realToken1,
          oracleAddress: oracleAddress,
        },
        extendedLpFee: 500,
        protocolFee: 500,
        initialMarginRatio: 2,
        maintainanceMarginRatio: 3,
        twapDuration: 2,
        whitelisted: false,
      },
      1,
    );

    const eventFilter1 = VPoolFactory.filters.PoolInitlized();
    const events1 = await VPoolFactory.queryFilter(eventFilter1, 'latest');
    vTokenAddress1 = events1[0].args[1];
    // console.log('vTokenAddres1', vTokenAddress);
    // console.log('VPoolFactoryAddress1', VPoolFactory.address);
    // console.log('Vwrapper1', events1[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events1[0].args[2]);
    await VPoolWrapper.liquidityChange(-10, 10, 10000000000000);

    const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
    VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;

    constants = await VPoolFactory.constants();
  });

  after(deactivateMainnetFork);

  describe('Functions', () => {
    it('Activate', async () => {
      await VTokenPositionSet.init(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVBase.balance).to.eq(0);
    });

    it('Update', async () => {
      await VTokenPositionSet.update(
        {
          vBaseIncrease: 10,
          vTokenIncrease: 20,
          traderPositionIncrease: 30,
        },
        vTokenAddress,
        constants,
      );
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(20);
      expect(resultVToken.netTraderPosition).to.eq(30);
      expect(resultVBase.balance).to.eq(10);
    });

    it('Realized Funding Payment', async () => {
      await VTokenPositionSet.realizeFundingPaymentToAccount(vTokenAddress, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken[1]).to.eq((20n * 1n) << 128n); //sumAChk
      expect(resultVBase.balance).to.eq(-590);
    });
  });

  describe('Token Swaps (Token Amount)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress, 4, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress1, 2, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVBase.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Token Swaps (Token Notional)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress, 16000, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress1, 8000, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVBase.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Liquidity Change', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
    });

    it('Add Liquidity', async () => {
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, 100, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);

      expect(resultVToken.balance).to.eq(-100);
      // expect(resultVToken.netTraderPosition).to.eq(-100);
      expect(resultVBase.balance).to.eq(-400000);
    });

    it('Remove Liquidity', async () => {
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, -50, constants);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);

      expect(resultVToken.balance).to.eq(-50);
      // expect(resultVToken.netTraderPosition).to.eq(-50);
      expect(resultVBase.balance).to.eq(-200000);
    });
  });

  describe('Liquididate Liquidity Positions (For a token)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
      await VTokenPositionSet.liquidityChange(vTokenAddress, -100, 100, 100, constants);
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, 100, constants);
    });

    it('Liquidate Liquidity Position', async () => {
      let resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      let resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(-200);
      expect(resultVBase.balance).to.eq(-800000);

      await VTokenPositionSet.liquidateLiquidityPositions(vTokenAddress, constants);

      resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      resultVBase = await VTokenPositionSet.getPositionDetails(VBase.address);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVBase.balance).to.eq(0);
    });
  });
});
