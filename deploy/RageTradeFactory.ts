import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
  ClearingHouse__factory,
  InsuranceFund__factory,
  ProxyAdmin__factory,
  VQuote__factory,
} from '../typechain-types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get, read, save },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();
  const clearingHouseLogic = await get('ClearingHouseLogic');
  const vPoolWrapperLogic = await get('VPoolWrapperLogic');
  const insuranceFundLogic = await get('InsuranceFundLogic');
  const settlementToken = await get('SettlementToken');
  const nativeOracle = await get('NativeOracle');

  const deployment = await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      settlementToken.address,
      nativeOracle.address,
    ],
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
};

export default func;

func.tags = ['RageTradeFactory'];
