import hre from 'hardhat';
import { smock } from '@defi-wonderland/smock';
import { constants } from './dummyConstants';
import { ethers } from 'ethers';
import { VPoolFactory } from '../../typechain-types';
import { setupVPool } from './setup-vPool';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

export async function setupWrapper({
  vPriceInitial,
  rPriceInitial,
  signer,
}: {
  vPriceInitial: number;
  rPriceInitial: number;
  signer?: SignerWithAddress;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  const { vPool, vBase, vToken, oracle, isToken0 } = await setupVPool({ vPriceInitial, rPriceInitial });

  const wrapperDeployer = await smock.fake<VPoolFactory>('VPoolFactory', {
    address: signer.address,
  });

  const { AddressZero, HashZero } = ethers.constants;

  wrapperDeployer.parameters.returns([
    vToken.address,
    vPool.address,
    2, // initialMargin
    3, // maintainanceMargin
    60, // twapDuration
    [
      AddressZero, // VPOOL_FACTORY
      vBase.address, // VBASE_ADDRESS
      AddressZero, //  UNISWAP_FACTORY_ADDRESS
      500, // DEFAULT_FEE_TIER
      HashZero, // POOL_BYTE_CODE_HASH
      HashZero, // WRAPPER_BYTE_CODE_HASH
    ],
  ]);

  const vPoolWrapper = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();
  await vPoolWrapper.setOracle(oracle.address);

  vBase.setVariable('isAuth', { [vPoolWrapper.address]: true });
  vToken.setVariable('vPoolWrapper', vPoolWrapper.address);

  return { vPoolWrapper, vPool, vBase, vToken, oracle, isToken0 };
}
