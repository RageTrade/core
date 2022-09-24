import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { priceToPriceX128 } from '@ragetrade/sdk';

import { IUniswapV3Pool__factory, VPoolWrapper__factory, VToken__factory } from '../typechain-types';
import {
  IClearingHouseStructures,
  PoolInitializedEvent,
  RageTradeFactory,
  VTokenDeployer,
} from '../typechain-types/artifacts/contracts/protocol/RageTradeFactory';
import { getNetworkInfo, waitConfirmations } from './network-info';
import { ethers } from 'ethers';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { get, deploy, execute, save },
    getNamedAccounts,
  } = hre;

  // checks if pool for ETH was already deployed
  let isAlreadyDeployed = false;
  try {
    await get('ETH-vToken');
    isAlreadyDeployed = true;
  } catch (e) {
    console.log((e as Error).message);
  }

  if (isAlreadyDeployed) {
    console.log('vETH already setup, hence skipping deployment');
  } else {
    const { deployer } = await getNamedAccounts();

    let ethIndexOracleDeployment;
    const { CHAINLINK_ETH_USD_ORACLE, FLAGS_INTERFACE } = getNetworkInfo();

    // uses chainlink oracle if provided, else uses OracleMock
    if (CHAINLINK_ETH_USD_ORACLE) {
      ethIndexOracleDeployment = await deploy('ETH-IndexOracle', {
        contract: 'ChainlinkOracle',
        args: [CHAINLINK_ETH_USD_ORACLE, FLAGS_INTERFACE ?? ethers.constants.AddressZero, 18, 6],
        from: deployer,
        log: true,
        waitConfirmations,
      });
    } else {
      console.log('CHAINLINK_ETH_USD_ORACLE not provided, using OracleMock as IndexOracle');
      ethIndexOracleDeployment = await deploy('ETH-IndexOracle', {
        contract: 'OracleMock',
        from: deployer,
        log: true,
      });
      // setting initial price as 2000 ETH-USD for the index oracle
      await execute(
        'ETH-IndexOracle',
        { from: deployer, waitConfirmations, log: true },
        'setPriceX128',
        await priceToPriceX128(2000, 6, 18),
      );
    }

    const deployVTokenParams: VTokenDeployer.DeployVTokenParamsStruct = {
      vTokenName: 'Virtual Ether (Rage Trade)',
      vTokenSymbol: 'vETH',
      cTokenDecimals: 18,
    };

    const poolInitialSettings: IClearingHouseStructures.PoolSettingsStruct = {
      initialMarginRatioBps: 2000,
      maintainanceMarginRatioBps: 1000,
      maxVirtualPriceDeviationRatioBps: 1000, // 10%
      twapDuration: 900,
      isAllowedForTrade: true,
      isCrossMargined: true,
      oracle: ethIndexOracleDeployment.address, // using deployed oracle address here
    };

    const params: RageTradeFactory.InitializePoolParamsStruct = {
      deployVTokenParams,
      poolInitialSettings,
      liquidityFeePips: 1000,
      protocolFeePips: 500,
      slotsToInitialize: 100,
    };

    const tx = await execute(
      'RageTradeFactory',
      {
        from: deployer,
        waitConfirmations,
        estimateGasExtra: 10_000, // to account for dependency on prevBlockHash
        log: true,
        gasLimit: 10_000_000,
      },
      'initializePool',
      params,
    );

    const event = tx.events?.find(event => event?.event === 'PoolInitialized') as unknown as PoolInitializedEvent;
    if (!event) {
      throw new Error('The event RageTradeFactory.PoolInitialized does not seem to be emitted');
    }

    await save('ETH-vToken', { abi: VToken__factory.abi, address: event.args.vToken });
    console.log('saved "ETH-vToken":', event.args.vToken);

    await save('ETH-vPool', { abi: IUniswapV3Pool__factory.abi, address: event.args.vPool });
    console.log('saved "ETH-vPool":', event.args.vPool);

    await save('ETH-vPoolWrapper', { abi: VPoolWrapper__factory.abi, address: event.args.vPoolWrapper });
    console.log('saved "ETH-vPoolWrapper":', event.args.vPoolWrapper);
  }
};

export default func;

func.tags = ['vETH'];
func.dependencies = ['RageTradeFactory'];
