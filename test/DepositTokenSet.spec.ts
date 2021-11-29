import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { calculateAddressFor } from './utils/create-addresses';
import { DepositTokenSetTest, VPoolFactory, ClearingHouse, OracleMock, RealTokenMock, ERC20 } from '../typechain-types';

import { utils } from 'ethers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { smock } from '@defi-wonderland/smock';

describe('DepositTokenSet Library', () => {
  let test: DepositTokenSetTest;

  let vTokenAddress: string;
  let vTokenAddress1: string;

  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;

  let oracle: OracleMock;
  let oracle1: OracleMock;

  let realToken: RealTokenMock;
  let realToken1: RealTokenMock;

  let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

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
      500,
      500,
      initialMargin,
      maintainanceMargin,
      twapDuration,
    );

    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPool = events[0].args[0];
    const vTokenAddress = events[0].args[1];
    const vPoolWrapper = events[0].args[2];

    // console.log('VBASE ADDRESS: ', vBaseAddress);
    // console.log('Wrapper Address: ', vPoolWrapper);
    // console.log('Clearing House Address: ', clearingHouse.address);
    // console.log('Oracle Address: ', oracleAddress);
    return { vTokenAddress, realToken, oracle };
  }
  before(async () => {
    await activateMainnetFork();

    const rBase = await smock.fake<ERC20>('ERC20');
    rBase.decimals.returns(18);
    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    const vBase = await vBaseFactory.deploy(rBase.address);
    vBaseAddress = vBase.address;

    signers = await hre.ethers.getSigners();

    const futureVPoolFactoryAddress = await calculateAddressFor(signers[0], 2);
    const futureInsurnaceFundAddress = await calculateAddressFor(signers[0], 3);

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

    let out = await initializePool(VPoolFactory, 20, 10, 1);
    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;

    out = await initializePool(VPoolFactory, 20, 10, 1);
    vTokenAddress1 = out.vTokenAddress;
    oracle1 = out.oracle;
    realToken1 = out.realToken;

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy();

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;

    constants = await VPoolFactory.constants();
  });

  describe('#Single Token', () => {
    before(async () => {
      test.init(vTokenAddress);
    });
    it('Add Margin', async () => {
      test.increaseBalance(vTokenAddress, 100, constants);
      const balance = await test.getBalance(vTokenAddress);
      expect(balance).to.eq(100);
    });
    it('Remove Margin', async () => {
      test.decreaseBalance(vTokenAddress, 50, constants);
      const balance = await test.getBalance(vTokenAddress);
      expect(balance).to.eq(50);
    });
    it('Deposit Market Value', async () => {
      await oracle.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));
      const marketValue = await test.getAllDepositAccountMarketValue(constants);
      expect(marketValue).to.eq(20000);
    });
  });

  describe('#Multiple Tokens', () => {
    before(async () => {
      test.init(vTokenAddress1);
      test.cleanDeposits(constants);
    });
    it('Add Margin', async () => {
      test.increaseBalance(vTokenAddress, 50, constants);
      let balance = await test.getBalance(vTokenAddress);
      expect(balance).to.eq(50);

      test.increaseBalance(vTokenAddress1, 100, constants);
      balance = await test.getBalance(vTokenAddress1);
      expect(balance).to.eq(100);
    });
    it('Deposit Market Value (Price1)', async () => {
      await oracle.setSqrtPrice(BigNumber.from(40).mul(BigNumber.from(2).pow(96)));
      await oracle1.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue(constants);
      expect(marketValue).to.eq(120000);
    });
    it('Deposit Market Value (Price2)', async () => {
      await oracle.setSqrtPrice(BigNumber.from(10).mul(BigNumber.from(2).pow(96)));
      await oracle1.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue(constants);
      expect(marketValue).to.eq(45000);
    });
  });
});
