import hre, { ethers } from 'hardhat';
import { FakeContract, MockContract, smock } from '@defi-wonderland/smock';
import {
  ERC20,
  IOracle,
  IUniswapV3PoolDeployer,
  UniswapV3Pool__factory,
  VToken__factory,
  VBase__factory,
  VBase,
} from '../../typechain-types';
import { BigNumber } from '@ethersproject/bignumber';
import { getCreateAddress } from './create-addresses';
import { toQ96 } from './fixed-point';
import { parseEther, parseUnits } from '@ethersproject/units';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { priceToSqrtPriceX96 } from './price-tick';

export interface SetupArgs {
  vPriceInitial: number;
  rPriceInitial: number;
  vBaseDecimals?: number;
  vTokenDecimals?: number;
  signer?: SignerWithAddress;
  vBase?: MockContract<VBase>;
}

export async function setupVPool({
  vPriceInitial,
  rPriceInitial,
  vBaseDecimals,
  vTokenDecimals,
  signer,
  vBase,
}: SetupArgs) {
  vBaseDecimals = vBaseDecimals ?? 6;
  vTokenDecimals = vTokenDecimals ?? 18;
  signer = signer ?? (await hre.ethers.getSigners())[0];

  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  if (!vBase) {
    // setting up virtual base
    const realBase = await smock.fake<ERC20>('ERC20');
    realBase.decimals.returns(vBaseDecimals);
    const VBase__factory = await smock.mock<VBase__factory>('VBase', signer); // await hre.ethers.getContractFactory('VBase');
    vBase = await VBase__factory.deploy(realBase.address);
    hre.tracer.nameTags[vBase.address] = 'vBase';
  }

  // setting up virtual token
  const realToken = await smock.fake<ERC20>('ERC20');
  realToken.decimals.returns(vTokenDecimals);
  const VToken__factory = await smock.mock<VToken__factory>('VToken', signer); // await hre.ethers.getContractFactory('VToken');
  const vPoolWrapperAddressCalculated = signer.address; // ethers.constants.AddressZero;
  const vToken = await VToken__factory.deploy(
    'vETH',
    'vETH',
    realToken.address,
    oracle.address,
    vPoolWrapperAddressCalculated,
  );
  hre.tracer.nameTags[vToken.address] = 'vToken';

  await oracle.setSqrtPrice(toQ96(Math.sqrt(rPriceInitial)));

  const v3Deployer = await smock.fake<IUniswapV3PoolDeployer>('IUniswapV3PoolDeployer', {
    address: signer.address,
  });

  const isToken0 = BigNumber.from(vBase.address).gt(vToken.address);
  const token0 = isToken0 ? vToken.address : vBase.address;
  const token1 = isToken0 ? vBase.address : vToken.address;
  const fee = 500;
  const tickSpacing = 10;
  v3Deployer.parameters.returns([signer.address, token0, token1, fee, tickSpacing]);

  const vPool = await new UniswapV3Pool__factory(signer).deploy();
  hre.tracer.nameTags[vPool.address] = 'vPool';

  const sqrtPrice = await priceToSqrtPriceX96(vPriceInitial, vBase, vToken);
  await vPool.initialize(sqrtPrice);

  return { vPool, vBase, vToken, oracle, isToken0 };
}
