import hre, { ethers } from 'hardhat';
import { FakeContract, smock } from '@defi-wonderland/smock';
import { ClearingHouse, ERC20, VBase, RageTradeFactory } from '../../typechain-types';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from './create-addresses';
// import { ConstantsStruct } from '../../typechain-types/ClearingHouse';

export async function testSetup({
  signer,
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
  whitelisted,
}: {
  signer?: SignerWithAddress;
  initialMarginRatio: number;
  maintainanceMarginRatio: number;
  twapDuration: number;
  whitelisted: boolean;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //RealBase
  const realBase = await smock.fake<ERC20>('ERC20');
  realBase.decimals.returns(6);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
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
    clearingHouseLogic.address,
    vPoolWrapperLogic.address,
    insuranceFundLogic.address,
    realBase.address,
    nativeOracle.address,
  );

  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());

  const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());

  //VBase
  const vBase = await hre.ethers.getContractAt('VBase', await rageTradeFactory.vBase());

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20', { address: ethers.constants.AddressZero });
  realToken.decimals.returns(18);

  // const vPoolWrapperDeployer = await (
  //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  // ).deploy(futureVPoolFactoryAddress);

  // const vPoolFactory = await (
  //   await hre.ethers.getContractFactory('VPoolFactory')
  // ).deploy(
  //   vBase.address,
  //   clearingHouse.address,
  //   vPoolWrapperDeployer.address,
  //   UNISWAP_FACTORY_ADDRESS,
  //   DEFAULT_FEE_TIER,
  //   UNISWAP_V3_POOL_BYTE_CODE_HASH,
  // );

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vTest',
      vTokenSymbol: 'vTest',
      rTokenDecimals: 18,
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
    slotsToInitialize: 100,
  });

  const eventFilter = rageTradeFactory.filters.PoolInitlized();
  const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];
  // const constants = (await clearingHouse.protocolInfo()).constants;

  return {
    realBase,
    vBase,
    oracle,
    clearingHouse,
    clearingHouseLogic,
    rageTradeFactory,
    vPoolAddress,
    vTokenAddress,
    vPoolWrapperAddress,
    insuranceFund,
    // constants,
  };
}

export async function testSetupBase(signer?: SignerWithAddress) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //RealBase
  const realBase = await smock.fake<ERC20>('ERC20');
  realBase.decimals.returns(6);

  //VBase
  // const vBase = await smock.fake<VBase>('VBase', { address: '0x8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' });
  // vBase.decimals.returns(6);

  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 3);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 4);

  // const vPoolWrapperDeployer = await (
  //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  // ).deploy(futureVPoolFactoryAddress);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
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
    clearingHouseLogic.address,
    vPoolWrapperLogic.address,
    insuranceFundLogic.address,
    realBase.address,
    nativeOracle.address,
  );

  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());

  const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());

  const vBase = await hre.ethers.getContractAt('VBase', await rageTradeFactory.vBase());
  // const constants = (await clearingHouse.protocolInfo()).constants;

  return {
    realBase,
    vBase,
    clearingHouse,
    rageTradeFactory,
    insuranceFund,
    oracle,
  };
}

export async function testSetupToken({
  signer,
  decimals,
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
  whitelisted,
  rageTradeFactory,
}: {
  signer?: SignerWithAddress;
  decimals: number;
  initialMarginRatio: number;
  maintainanceMarginRatio: number;
  twapDuration: number;
  whitelisted: boolean;
  rageTradeFactory: RageTradeFactory;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20');
  realToken.decimals.returns(decimals);

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vTest',
      vTokenSymbol: 'vTest',
      rTokenDecimals: 18,
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
    slotsToInitialize: 100,
  });
  const eventFilter = rageTradeFactory.filters.PoolInitlized();
  const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];

  return {
    oracle: oracle,
    vPoolAddress: vPoolAddress,
    vTokenAddress: vTokenAddress,
    vPoolWrapperAddress: vPoolWrapperAddress,
  };
}
