import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { ethers } from 'ethers';

import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { calculateAddressFor } from './utils/create-addresses';
import {
  AccountTest,
  VPoolFactory,
  ClearingHouse,
  ERC20,
  RealTokenMock,
  OracleMock,
  IERC20,
  ClearingHouseTest,
} from '../typechain-types';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { config } from 'dotenv';
import { stealFunds, tokenAmount } from './utils/stealFunds';

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

  let signers: SignerWithAddress[];
  let admin: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

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
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();

    await VPoolFactory.initializePool(
      'vWETH',
      'vWETH',
      realToken.address,
      oracle.address,
      initialMargin,
      maintainanceMargin,
      twapDuration,
    );

    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    return { vTokenAddress, realToken, oracle };
  }

  before(async () => {
    await activateMainnetFork();

    dummyTokenAddress = ethers.utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);

    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    const vBase = await vBaseFactory.deploy(REAL_BASE);
    vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    admin = signers[0];
    user1 = signers[1];
    user2 = signers[2];

    const futureVPoolFactoryAddress = await calculateAddressFor(admin, 2);
    const futureInsurnaceFundAddress = await calculateAddressFor(admin, 3);

    const VPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);

    clearingHouseTest = await (
      await hre.ethers.getContractFactory('ClearingHouseTest')
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

    let out = await initializePool(VPoolFactory, 20, 10, 1);
    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;

    constants = await VPoolFactory.constants();

    rBase = await hre.ethers.getContractAt('IERC20', REAL_BASE);
  });

  after(async () => {
    await deactivateMainnetFork();
  });

  describe('#StealFunds', () => {
    it('Steal Funds', async () => {
      await stealFunds(REAL_BASE, 6, user1.address, '10000', whaleForBase);
      await stealFunds(REAL_BASE, 6, user2.address, '10000', whaleForBase);
      expect(await rBase.balanceOf(user1.address)).to.eq(tokenAmount('10000', 6));
      expect(await rBase.balanceOf(user2.address)).to.eq(tokenAmount('10000', 6));
    });
  });
});
