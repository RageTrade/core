import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
  IUniswapV3Pool__factory,
  RageTradeFactory__factory,
  VPoolWrapper__factory,
  VToken__factory,
} from '../typechain-types';
import { ethers } from 'ethers';
import { TypedEvent } from '../typechain-types/common';
import { PoolInitializedEvent } from '../typechain-types/RageTradeFactory';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { get, deploy, execute, save },
    getNamedAccounts,
  } = hre;

  let alreadyDeployed = false;
  try {
    await get('ETH-vToken');
    alreadyDeployed = true;
  } catch {}

  if (!alreadyDeployed) {
    const { deployer } = await getNamedAccounts();

    // deploying an index price oracle for the token
    const ethIndexOracleDeployment = await deploy('ETH-IndexOracle', {
      contract: 'OracleMock', // TODO change to ChainLinkOracle
      from: deployer,
      log: true,
    });
    await execute('ETH-IndexOracle', { from: deployer }, 'setSqrtPriceX96', '0x03f2102ff45be0b5f51f3d');

    // TODO add typecheck here, else life can get too hard when any breaking change would take place in initializePool signature
    const tx = await execute('RageTradeFactory', { from: deployer }, 'initializePool', {
      deployVTokenParams: {
        vTokenName: 'Virtual ETH (Rage Trade)',
        vTokenSymbol: 'vETH',
        cTokenDecimals: 18,
      },
      poolInitialSettings: {
        initialMarginRatio: 20000,
        maintainanceMarginRatio: 10000,
        twapDuration: 60,
        supported: true,
        isCrossMargined: true,
        oracle: ethIndexOracleDeployment.address,
      },
      liquidityFeePips: 1000,
      protocolFeePips: 500,
      slotsToInitialize: 0,
    });

    const poolInitializedLog = tx.events?.find(
      event => event?.event === 'PoolInitialized',
    ) as unknown as PoolInitializedEvent;
    if (!poolInitializedLog) {
      throw new Error('PoolInitialized log not found');
    }

    await save('ETH-vToken', { abi: VToken__factory.abi, address: poolInitializedLog.args.vToken });
    await save('ETH-vPool', { abi: IUniswapV3Pool__factory.abi, address: poolInitializedLog.args.vPool });
    await save('ETH-vPoolWrapper', { abi: VPoolWrapper__factory.abi, address: poolInitializedLog.args.vPoolWrapper });
  }
};

export default func;

func.tags = ['vETH'];
