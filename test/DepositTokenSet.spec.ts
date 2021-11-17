import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';

import { DepositTokenSetTest, ClearingHouse, RealTokenMock } from '../typechain-types';
import { utils } from 'ethers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH } from './utils/realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

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

  async function deployPool(
    clearingHouse: ClearingHouse,
    initialMargin: BigNumberish,
    maintainanceMargin: BigNumberish,
    twapDuration: BigNumberish,
  ) {
    await clearingHouse.initializePool(
      'vWETH',
      'vWETH',
      realToken.address,
      oracleAddress,
      initialMargin,
      maintainanceMargin,
      twapDuration,
    );

    const eventFilter = clearingHouse.filters.poolInitlized();
    const events = await clearingHouse.queryFilter(eventFilter, 'latest');
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

    const vBaseFactory = await hre.ethers.getContractFactory('VBase');
    const vBase = await vBaseFactory.deploy();
    vBaseAddress = vBase.address;

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();
    oracleAddress = oracle.address;

    const clearingHouseFactory = await hre.ethers.getContractFactory('ClearingHouse');
    const clearingHouse = await clearingHouseFactory.deploy(
      vBaseAddress,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );
    await vBase.transferOwnership(clearingHouse.address);

    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    realToken = await realTokenFactory.deploy();

    await deployPool(clearingHouse, 20, 10, 1);

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy();

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;

    constants = await clearingHouse.constants();
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
