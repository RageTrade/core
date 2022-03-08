import hre, { ethers } from 'hardhat';
import { FakeContract, MockContract, smock } from '@defi-wonderland/smock';
import {
  ERC20,
  IOracle,
  IUniswapV3PoolDeployer,
  UniswapV3Pool__factory,
  VToken__factory,
  VQuote__factory,
  VQuote,
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
  vQuoteDecimals?: number;
  vTokenDecimals?: number;
  uniswapFee?: number;
  liquidityFee?: number;
  protocolFee?: number;
  signer?: SignerWithAddress;
  vQuote?: MockContract<VQuote>;
}

export async function setupVPool({
  vPriceInitial,
  rPriceInitial,
  vQuoteDecimals,
  vTokenDecimals,
  uniswapFee,
  signer,
  vQuote,
}: SetupArgs) {
  vQuoteDecimals = vQuoteDecimals ?? 6;
  vTokenDecimals = vTokenDecimals ?? 18;
  uniswapFee = uniswapFee ?? 500;
  signer = signer ?? (await hre.ethers.getSigners())[0];

  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  if (!vQuote) {
    // setting up virtual base
    const VQuote__factory = await smock.mock<VQuote__factory>('VQuote', signer); // await hre.ethers.getContractFactory('VQuote');
    vQuote = await VQuote__factory.deploy(vQuoteDecimals);
    hre.tracer.nameTags[vQuote.address] = 'vQuote';
  }

  // setting up virtual token
  const VToken__factory = await smock.mock<VToken__factory>('VToken', signer); // await hre.ethers.getContractFactory('VToken');
  const vPoolWrapperAddressCalculated = signer.address; // ethers.constants.AddressZero;
  const vToken = await VToken__factory.deploy('vETH', 'vETH', vTokenDecimals);
  await vToken.setVPoolWrapper(vPoolWrapperAddressCalculated);
  hre.tracer.nameTags[vToken.address] = 'vToken';

  await oracle.setSqrtPriceX96(await priceToSqrtPriceX96(rPriceInitial, vQuote, vToken));

  const v3Deployer = await smock.fake<IUniswapV3PoolDeployer>(
    '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3PoolDeployer.sol:IUniswapV3PoolDeployer',
    {
      address: signer.address,
    },
  );

  const token0 = vToken.address;
  const token1 = vQuote.address;
  const fee = uniswapFee;
  const tickSpacing = 10;
  v3Deployer.parameters.returns([signer.address, token0, token1, fee, tickSpacing]);

  const vPool = await new UniswapV3Pool__factory(signer).deploy();
  hre.tracer.nameTags[vPool.address] = 'vPool';

  const sqrtPrice = await priceToSqrtPriceX96(vPriceInitial, vQuote, vToken);
  await vPool.initialize(sqrtPrice);

  return { vPool, vQuote, vToken, oracle };
}
