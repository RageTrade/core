import { parseUnits } from 'ethers/lib/utils';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { InsuranceFund__factory, ProxyAdmin__factory, VQuote__factory } from '../typechain-types';
import { getNetworkInfo, waitConfirmations } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get, read, save, execute },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();
  const clearingHouseLogic = await get('ClearingHouseLogic');
  const vPoolWrapperLogic = await get('VPoolWrapperLogic');
  const insuranceFundLogic = await get('InsuranceFundLogic');
  const settlementToken = await get('SettlementToken');
  const settlementTokenOracle = await get('SettlementTokenOracle');

  // deploy RageTradeFactory and save it to the deployments
  await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      settlementToken.address,
      settlementTokenOracle.address,
    ],
    waitConfirmations,
    estimateGasExtra: 1000000, // provide extra gas than estimated
  });

  // vQuote is deployed in RageTradeFactory constructor
  const vQuoteAddress = await read('RageTradeFactory', 'vQuote');
  await save('VQuote', { abi: VQuote__factory.abi, address: vQuoteAddress });
  console.log('saved "VQuote":', vQuoteAddress);

  // clearing house is deployed in RageTradeFactory constructor
  const clearingHouseAddress = await read('RageTradeFactory', 'clearingHouse');
  await save('ClearingHouse', { abi: clearingHouseLogic.abi, address: clearingHouseAddress });
  console.log('saved "ClearingHouse":', clearingHouseAddress);

  // deploy ClearingHouseLens and save it to the deployments
  await deploy('ClearingHouseLens', {
    from: deployer,
    log: true,
    args: [clearingHouseAddress],
    waitConfirmations,
  });

  // initialize protocol settings
  await execute(
    'ClearingHouse',
    { from: deployer, waitConfirmations },
    'updateProtocolSettings',
    {
      rangeLiquidationFeeFraction: 1500,
      tokenLiquidationFeeFraction: 3000,
      insuranceFundFeeShareBps: 5000,
      maxRangeLiquidationFees: 100000000,
      closeFactorMMThresholdBps: 7500,
      partialLiquidationCloseFactorBps: 5000,
      liquidationSlippageSqrtToleranceBps: 150, // sqrt
      minNotionalLiquidatable: 100000000,
    },
    parseUnits('10', 6), // removeLimitOrderFee
    parseUnits('1', 6).div(100), // minimumOrderNotional
    parseUnits('20', 6), // minRequiredMargin
  );

  const proxyAdminAddress = await read('RageTradeFactory', 'proxyAdmin');
  await save('ProxyAdmin', { abi: ProxyAdmin__factory.abi, address: proxyAdminAddress });
  console.log('saved "ProxyAdmin":', proxyAdminAddress);

  const insuranceFundAddress = await read('ClearingHouse', 'insuranceFund');
  await save('InsuranceFund', { abi: InsuranceFund__factory.abi, address: insuranceFundAddress });
  console.log('saved "InsuranceFund":', insuranceFundAddress);

  // transfer governance to timelock
  const timelock = await get('TimelockController');
  await execute(
    'RageTradeFactory',
    { from: deployer, waitConfirmations },
    'initiateGovernanceTransfer',
    timelock.address,
  );
  await execute('ClearingHouse', { from: deployer, waitConfirmations }, 'initiateGovernanceTransfer', timelock.address);
  await execute('ProxyAdmin', { from: deployer, waitConfirmations }, 'transferOwnership', timelock.address);

  // transfer teamMultisig to multisig address
  const { multisigAddress } = getNetworkInfo(hre.network.config.chainId);
  await execute(
    'RageTradeFactory',
    { from: deployer, waitConfirmations },
    'initiateTeamMultisigTransfer',
    multisigAddress,
  );
  await execute(
    'ClearingHouse',
    { from: deployer, waitConfirmations },
    'initiateTeamMultisigTransfer',
    multisigAddress,
  );
};

export default func;

func.tags = ['RageTradeFactory', 'VQuote', 'ClearingHouse', 'ClearingHouseLens', 'ProxyAdmin', 'InsuranceFund'];
func.dependencies = [
  'ClearingHouseLogic',
  'VPoolWrapperLogic',
  'InsuranceFundLogic',
  'SettlementToken',
  'SettlementTokenOracle',
  'TimelockController',
];
