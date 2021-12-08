import hre, { ethers } from 'hardhat';
import { smock } from '@defi-wonderland/smock';
import { ERC20, VBase } from '../../typechain-types';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from './create-addresses';

export async function testSetup({
  signer,
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
  isVTokenToken0,
}: {
  signer?: SignerWithAddress;
  initialMarginRatio: number;
  maintainanceMarginRatio: number;
  twapDuration: number;
  isVTokenToken0: boolean;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //RealBase
  const realBase = await smock.fake<ERC20>('ERC20');
  realBase.decimals.returns(6);

  //VBase
  let vBaseAddress;
  if (isVTokenToken0) vBaseAddress = '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  else vBaseAddress = '0x0000000000000000000000000000000000000001'; // Uniswap reverts on 0
  const vBase = await smock.fake<VBase>('VBase', { address: vBaseAddress });
  vBase.decimals.returns(6);

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20', { address: ethers.constants.AddressZero });
  realToken.decimals.returns(18);

  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 2);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 3);

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

  await vPoolFactory.initializePool(
    'vTest',
    'vTest',
    realToken.address,
    oracle.address,
    500,
    500,
    initialMarginRatio,
    maintainanceMarginRatio,
    twapDuration,
  );

  const eventFilter = vPoolFactory.filters.PoolInitlized();
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
