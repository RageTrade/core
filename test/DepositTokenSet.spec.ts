import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
import {
  DepositTokenSetTest,
  RageTradeFactory,
  ClearingHouse,
  OracleMock,
  RealTokenMock,
  ERC20,
} from '../typechain-types';

import { utils } from 'ethers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './utils/realConstants';
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

  // let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

  async function initializePool(
    rageTradeFactory: RageTradeFactory,
    initialMarginRatio: BigNumberish,
    maintainanceMarginRatio: BigNumberish,
    twapDuration: BigNumberish,
  ) {
    const realTokenFactory = await hre.ethers.getContractFactory('RealTokenMock');
    const realToken = await realTokenFactory.deploy();

    const oracleFactory = await hre.ethers.getContractFactory('OracleMock');
    const oracle = await oracleFactory.deploy();

    await rageTradeFactory.initializePool({
      deployVTokenParams: {
        vTokenName: 'vWETH',
        vTokenSymbol: 'vWETH',
        rTokenAddress: realToken.address,
        oracleAddress: oracle.address,
      },
      rageTradePoolInitialSettings: {
        initialMarginRatio,
        maintainanceMarginRatio,
        twapDuration,
        whitelisted: false,
        oracle: oracle.address,
      },
      liquidityFeePips: 500,
      protocolFeePips: 500,
    });

    const eventFilter = rageTradeFactory.filters.PoolInitlized();
    const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
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

    const futureVPoolFactoryAddress = await getCreateAddressFor(signers[0], 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(signers[0], 4);

    // const VPoolWrapperDeployer = await (
    //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    // ).deploy(futureVPoolFactoryAddress);

    const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const clearingHouseLogic = await (
      await hre.ethers.getContractFactory('ClearingHouse', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy();

    const insuranceFundAddressComputed = await getCreateAddressFor(signers[0], 1);

    const rageTradeFactory = await (
      await hre.ethers.getContractFactory('RageTradeFactory')
    ).deploy(
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      rBase.address,
      insuranceFundAddressComputed,
      UNISWAP_V3_FACTORY_ADDRESS,
      UNISWAP_V3_DEFAULT_FEE_TIER,
      UNISWAP_V3_POOL_BYTE_CODE_HASH,
    );
    const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());

    const InsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(rBase.address, clearingHouse.address);

    // await vBase.transferOwnership(VPoolFactory.address);

    let out = await initializePool(rageTradeFactory, 20, 10, 1);
    vTokenAddress = out.vTokenAddress;
    oracle = out.oracle;
    realToken = out.realToken;

    out = await initializePool(rageTradeFactory, 20, 10, 1);
    vTokenAddress1 = out.vTokenAddress;
    oracle1 = out.oracle;
    realToken1 = out.realToken;

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy();

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;

    // constants = await VPoolFactory.constants();

    const basePoolObj = await clearingHouse.rageTradePools(vBase.address);
    await test.registerPool(vBase.address, basePoolObj);

    const vTokenPoolObj = await clearingHouse.rageTradePools(vTokenAddress);
    await test.registerPool(vTokenAddress, vTokenPoolObj);

    const vTokenPoolObj1 = await clearingHouse.rageTradePools(vTokenAddress1);
    await test.registerPool(vTokenAddress1, vTokenPoolObj1);

    await test.setVBaseAddress(vBase.address);
  });

  describe('#Single Token', () => {
    before(async () => {
      await test.init(vTokenAddress);
    });
    it('Add Margin', async () => {
      await test.increaseBalance(vBaseAddress, 100);
      const balance = await test.getBalance(vBaseAddress);
      expect(balance).to.eq(100);
    });
    it('Remove Margin', async () => {
      await test.decreaseBalance(vBaseAddress, 50);
      const balance = await test.getBalance(vBaseAddress);
      expect(balance).to.eq(50);
    });
    it('Deposit Market Value', async () => {
      // await oracle.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));
      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(50);
    });
  });

  describe('#Multiple Tokens', () => {
    before(async () => {
      test.init(vTokenAddress1);
      test.cleanDeposits();
    });
    it('Add Margin', async () => {
      test.increaseBalance(vBaseAddress, 50);
      let balance = await test.getBalance(vBaseAddress);
      expect(balance).to.eq(50);

      test.increaseBalance(vTokenAddress1, 100);
      balance = await test.getBalance(vTokenAddress1);
      expect(balance).to.eq(100);
    });
    it('Deposit Market Value (Price1)', async () => {
      await oracle1.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(40050);
    });
    it('Deposit Market Value (Price2)', async () => {
      await oracle1.setSqrtPrice(BigNumber.from(10).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(10050);
    });
  });
});
