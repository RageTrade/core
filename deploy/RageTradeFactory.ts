import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
  ClearingHouse,
  ClearingHouse__factory,
  InsuranceFund__factory,
  IOracle__factory,
  ProxyAdmin__factory,
  VQuote__factory,
} from '../typechain-types';
import { IClearingHouseStructures } from '../typechain-types/artifacts/contracts/protocol/clearinghouse/ClearingHouse';
import { parseUnits } from 'ethers/lib/utils';
import { truncate } from '../test/utils/vToken';

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

  const deployment = await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [clearingHouseLogic.address, vPoolWrapperLogic.address, insuranceFundLogic.address, settlementToken.address],
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.push({
      name: 'RageTradeFactory',
      address: deployment.address,
    });
  }

  const vQuoteAddress = await read('RageTradeFactory', 'vQuote');
  await save('VQuote', { abi: VQuote__factory.abi, address: vQuoteAddress });
  console.log('saved "VQuote":', vQuoteAddress);
  await hre.tenderly.push({
    name: 'VQuote',
    address: vQuoteAddress,
  });

  const clearingHouseAddress = await read('RageTradeFactory', 'clearingHouse');
  await save('ClearingHouse', { abi: ClearingHouse__factory.abi, address: clearingHouseAddress });
  console.log('saved "ClearingHouse":', clearingHouseAddress);
  await hre.tenderly.push({
    name: 'TransparentUpgradeableProxy',
    address: clearingHouseAddress,
  });

  execute(
    'ClearingHouse',
    { from: deployer },
    'updateProtocolSettings',
    {
      rangeLiquidationFeeFraction: 1500,
      tokenLiquidationFeeFraction: 3000,
      insuranceFundFeeShareBps: 5000,
      maxRangeLiquidationFees: 100000000,
      closeFactorMMThresholdBps: 7500,
      partialLiquidationCloseFactorBps: 5000,
      liquidationSlippageSqrtToleranceBps: 150,
      minNotionalLiquidatable: 100000000,
    },
    parseUnits('10', 6), // removeLimitOrderFee
    parseUnits('1', 6).div(100), // minimumOrderNotional
    parseUnits('20', 6), // minRequiredMargin
  );

  const proxyAdminAddress = await read('RageTradeFactory', 'proxyAdmin');
  await save('ProxyAdmin', { abi: ProxyAdmin__factory.abi, address: proxyAdminAddress });
  console.log('saved "ProxyAdmin":', proxyAdminAddress);
  await hre.tenderly.push({
    name: 'ProxyAdmin',
    address: proxyAdminAddress,
  });

  const insuranceFundAddress = await read('ClearingHouse', 'insuranceFund');
  await save('InsuranceFund', { abi: InsuranceFund__factory.abi, address: insuranceFundAddress });
  console.log('saved "InsuranceFund":', insuranceFundAddress);
  await hre.tenderly.push({
    name: 'TransparentUpgradeableProxy',
    address: insuranceFundAddress,
  });

  const collateralInfo: IClearingHouseStructures.CollateralStruct = await read(
    'ClearingHouse',
    'getCollateralInfo',
    truncate(settlementToken.address),
  );
  await save('SettlementTokenOracle', { abi: IOracle__factory.abi, address: collateralInfo.settings.oracle });
  console.log('saved "SettlementTokenOracle":', collateralInfo.settings.oracle);
  await hre.tenderly.push({
    name: 'SettlementTokenOracle',
    address: collateralInfo.settings.oracle,
  });
};

export default func;

func.tags = ['RageTradeFactory'];
func.dependencies = ['ClearingHouseLogic', 'VPoolWrapperLogic', 'InsuranceFundLogic', 'SettlementToken'];
