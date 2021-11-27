import hre, { ethers } from 'hardhat';
import { FakeContract, MockContract, smock } from '@defi-wonderland/smock';
import { ERC20, VBase__factory } from '../../typechain-types';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { calculateAddressFor } from './create-addresses';

export async function testSetup({
  signer,
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
}: {
  signer?: SignerWithAddress;
  initialMarginRatio: number;
  maintainanceMarginRatio: number;
  twapDuration: number;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //RealBase
  const realBase = await smock.fake<ERC20>('ERC20');
  realBase.decimals.returns(6);

  //VBase
  const VBase__factory = await smock.mock<VBase__factory>('VBase', signer); // await hre.ethers.getContractFactory('VBase');
  const vBase = await VBase__factory.deploy(realBase.address);
  hre.tracer.nameTags[vBase.address] = 'vBase';

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20');
  realToken.decimals.returns(18);

  const futureVPoolFactoryAddress = await calculateAddressFor(signer, 2);
  const futureInsurnaceFundAddress = await calculateAddressFor(signer, 3);

  const vPoolWrapperDeployer = await (
    await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  ).deploy(futureVPoolFactoryAddress);

  const clearingHouse = await (
    await hre.ethers.getContractFactory('ClearingHouse')
  ).deploy(futureVPoolFactoryAddress, realBase.address, futureInsurnaceFundAddress);

  const vPoolFactory = await (
    await hre.ethers.getContractFactory('VPoolFactory')
  ).deploy(
    vBase.address,
    clearingHouse.address,
    vPoolWrapperDeployer.address,
    UNISWAP_FACTORY_ADDRESS,
    DEFAULT_FEE_TIER,
    POOL_BYTE_CODE_HASH,
  );
  await vBase.transferOwnership(vPoolFactory.address);
  await vPoolFactory.initializePool(
    'vTest',
    'vTest',
    realToken.address,
    oracle.address,
    initialMarginRatio,
    maintainanceMarginRatio,
    twapDuration,
  );

  const eventFilter = vPoolFactory.filters.poolInitlized();
  const events = await vPoolFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];
  const constants = await clearingHouse.constants();

  return {
    realbase: realBase,
    vBase: vBase,
    oracle: oracle,
    clearingHouse: clearingHouse,
    vPoolFactory: vPoolFactory,
    vPoolAddress: vPoolAddress,
    vTokenAddress: vTokenAddress,
    vPoolWrapperAddress: vPoolWrapperAddress,
    constants: constants,
  };
}
