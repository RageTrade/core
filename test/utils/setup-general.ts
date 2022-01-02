import hre, { ethers } from 'hardhat';
import { FakeContract, smock } from '@defi-wonderland/smock';
import { ClearingHouse, ERC20, VBase, VPoolFactory } from '../../typechain-types';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, UNISWAP_V3_POOL_BYTE_CODE_HASH, REAL_BASE } from './realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from './create-addresses';
import { ConstantsStruct } from '../../typechain-types/ClearingHouse';

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

  //VBase
  const vBase = await smock.fake<VBase>('VBase', { address: '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' });
  vBase.decimals.returns(6);

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20', { address: ethers.constants.AddressZero });
  realToken.decimals.returns(18);

  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 5);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 6);

  const vPoolWrapperDeployer = await (
    await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  ).deploy(futureVPoolFactoryAddress);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
      libraries: {
        Account: accountLib.address,
      },
    })
  ).deploy(futureVPoolFactoryAddress, realBase.address, futureInsurnaceFundAddress);

  const proxyAdmin = await (await hre.ethers.getContractFactory('ProxyAdmin')).deploy();
  const clearingHouseProxy = await (
    await hre.ethers.getContractFactory('TransparentUpgradeableProxy')
  ).deploy(clearingHouseLogic.address, proxyAdmin.address, '0x');
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', clearingHouseProxy.address);

  const vPoolFactory = await (
    await hre.ethers.getContractFactory('VPoolFactory')
  ).deploy(
    vBase.address,
    clearingHouse.address,
    vPoolWrapperDeployer.address,
    UNISWAP_FACTORY_ADDRESS,
    DEFAULT_FEE_TIER,
    UNISWAP_V3_POOL_BYTE_CODE_HASH,
  );

  await vPoolFactory.initializePool(
    {
      setupVTokenParams: {
        vTokenName: 'vTest',
        vTokenSymbol: 'vTest',
        realTokenAddress: realToken.address,
        oracleAddress: oracle.address,
      },
      extendedLpFee: 500,
      protocolFee: 500,
      initialMarginRatio,
      maintainanceMarginRatio,
      twapDuration,
      whitelisted: false,
    },
    0,
  );

  const eventFilter = vPoolFactory.filters.PoolInitlized();
  const events = await vPoolFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];
  const constants = await clearingHouse.constants();

  return {
    realBase,
    vBase,
    oracle,
    clearingHouse,
    proxyAdmin,
    clearingHouseLogic,
    clearingHouseProxy,
    vPoolFactory,
    vPoolAddress,
    vTokenAddress,
    vPoolWrapperAddress,
    constants,
  };
}

export async function testSetupBase(signer?: SignerWithAddress) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //RealBase
  const realBase = await smock.fake<ERC20>('ERC20');
  realBase.decimals.returns(6);

  //VBase
  const vBase = await smock.fake<VBase>('VBase', { address: '0x8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' });
  vBase.decimals.returns(6);

  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 3);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 4);

  const vPoolWrapperDeployer = await (
    await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  ).deploy(futureVPoolFactoryAddress);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouse = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
      libraries: {
        Account: accountLib.address,
      },
    })
  ).deploy(futureVPoolFactoryAddress, realBase.address, futureInsurnaceFundAddress);

  const vPoolFactory = await (
    await hre.ethers.getContractFactory('VPoolFactory')
  ).deploy(
    vBase.address,
    clearingHouse.address,
    vPoolWrapperDeployer.address,
    UNISWAP_FACTORY_ADDRESS,
    DEFAULT_FEE_TIER,
    UNISWAP_V3_POOL_BYTE_CODE_HASH,
  );

  const constants = await clearingHouse.constants();

  return {
    realbase: realBase,
    vBase: vBase,
    clearingHouse: clearingHouse,
    vPoolFactory: vPoolFactory,
    constants: constants,
  };
}

export async function testSetupToken({
  signer,
  decimals,
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
  whitelisted,
  vPoolFactory,
}: {
  signer?: SignerWithAddress;
  decimals: number;
  initialMarginRatio: number;
  maintainanceMarginRatio: number;
  twapDuration: number;
  whitelisted: boolean;
  vPoolFactory: VPoolFactory;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20');
  realToken.decimals.returns(decimals);

  await vPoolFactory.initializePool(
    {
      setupVTokenParams: {
        vTokenName: 'vTest',
        vTokenSymbol: 'vTest',
        realTokenAddress: realToken.address,
        oracleAddress: oracle.address,
      },
      extendedLpFee: 500,
      protocolFee: 500,
      initialMarginRatio,
      maintainanceMarginRatio,
      twapDuration,
      whitelisted: false,
    },
    0,
  );
  const eventFilter = vPoolFactory.filters.PoolInitlized();
  const events = await vPoolFactory.queryFilter(eventFilter, 'latest');
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
