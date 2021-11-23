import hre from 'hardhat';
import { expect } from 'chai';
import { network } from 'hardhat';
import { VPoolFactory, ERC20, VBase, VPoolWrapper } from '../typechain-types';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { BigNumber } from '@ethersproject/bignumber';
import { Contract } from '@ethersproject/contracts';
import { smock } from '@defi-wonderland/smock';
const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { calculateAddressFor } from './utils/create-addresses';

describe('VPoolWrapper', () => {
  let oracle: string;
  let VPoolFactory: VPoolFactory;
  let VPoolWrapper: VPoolWrapper;
  let VBase: VBase;
  let VTokenAddress: string;
  let VPoolAddress: string;
  let UniswapV3pool: Contract;
  let VToken: Contract;
  const liq: BigNumber = BigNumber.from(10000000000000);
  const lowerTick: BigNumber = BigNumber.from(-10);
  const higherTick: BigNumber = BigNumber.from(10);
  let signers: SignerWithAddress[];
  before(async () => {
    await activateMainnetFork();

    const realBase = await smock.fake<ERC20>('ERC20');
    realBase.decimals.returns(10);
    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy(realBase.address);
    oracle = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;

    signers = await hre.ethers.getSigners();
    const futureVPoolFactoryAddress = await calculateAddressFor(signers[0], 2);
    const VPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);
    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(futureVPoolFactoryAddress, REAL_BASE);
    VPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      VBase.address,
      clearingHouse.address,
      VPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );
    await VBase.transferOwnership(VPoolFactory.address);

    await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracle, 2, 3, 60);
    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    VTokenAddress = events[0].args[1];
    VPoolAddress = events[0].args[0];
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);

    UniswapV3pool = await hre.ethers.getContractAt('IUniswapV3Pool', VPoolAddress);
    VToken = await hre.ethers.getContractAt('IERC20', VTokenAddress);
  });

  after(deactivateMainnetFork);

  describe('Liquidity Change', () => {
    it('Add Liquidity', async () => {
      expect(await UniswapV3pool.liquidity()).to.eq(0);
      await VPoolWrapper.liquidityChange(lowerTick, higherTick, liq);
      expect(await UniswapV3pool.liquidity()).to.eq(liq);
    });
    it('Remove Liquidity', async () => {
      await VPoolWrapper.liquidityChange(lowerTick, higherTick, liq.mul(-1));
      expect(await UniswapV3pool.liquidity()).to.eq(0);
      // TODO add more checks
      // expect(await VToken.totalSupply()).to.eq(1); // Uniswap rounds down so amount0-1 is burned
      // expect(await VBase.totalSupply()).to.eq(1);
    });
  });
});
