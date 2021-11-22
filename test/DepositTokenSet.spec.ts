import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';

import { DepositTokenSetTest, VPoolFactory, ClearingHouse, RealTokenMock, ERC20 } from '../typechain-types';
import { utils } from 'ethers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { smock } from '@defi-wonderland/smock';

describe('DepositTokenSet Library', () => {
  let test: DepositTokenSetTest;

  let vTokenAddress: string;
  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;
  let oracleAddress: string;
  let realToken: RealTokenMock;
  let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

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
      initialMargin,
      maintainanceMargin,
      twapDuration,
    );

    const eventFilter = VPoolFactory.filters.poolInitlized();
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

    const VPoolFactoryFactory = await hre.ethers.getContractFactory('VPoolFactory');
    const VPoolFactory = await VPoolFactoryFactory.deploy(
      vBaseAddress,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );

    await vBase.transferOwnership(VPoolFactory.address);

    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    realToken = await realTokenFactory.deploy();

    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(VPoolFactory.address, REAL_BASE);
    await VPoolFactory.initBridge(clearingHouse.address);

    await initializePool(VPoolFactory, 20, 10, 1);

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy();

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;

    constants = await VPoolFactory.constants();
  });

  describe('#Functions', () => {
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
    it('Deposit Market Value');
    // , async() => {
    //     const marketValue = await test.getAllDepositAccountMarketValue(constants);
    //     expect(marketValue).to.eq(200000);
    // });
  });
});
