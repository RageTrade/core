import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
  ClearingHouse__factory,
  InsuranceFund__factory,
  ProxyAdmin__factory,
  VBase__factory,
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
  const rBase = await get('RBase');
  const nativeOracle = await get('NativeOracle');

  const deployment = await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      rBase.address,
      nativeOracle.address,
    ],
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.push({
      name: 'RageTradeFactory',
      address: deployment.address,
    });
  }

  const vBaseAddress = await read('RageTradeFactory', 'vBase');
  console.log('VBase : ', vBaseAddress);
  await save('VBase', { abi: VBase__factory.abi, address: vBaseAddress });

  await hre.tenderly.push({
    name: 'VBase',
    address: vBaseAddress,
  });

  const clearingHouseAddress = await read('RageTradeFactory', 'clearingHouse');
  console.log('ClearingHouse : ', clearingHouseAddress);
  await save('ClearingHouse', { abi: ClearingHouse__factory.abi, address: clearingHouseAddress });

  await hre.tenderly.push({
    name: 'TransparentUpgradeableProxy',
    address: clearingHouseAddress,
  });

  const proxyAdminAddress = await read('RageTradeFactory', 'proxyAdmin');
  console.log('ProxyAdmin : ', proxyAdminAddress);
  await save('ProxyAdmin', { abi: ProxyAdmin__factory.abi, address: proxyAdminAddress });

  await hre.tenderly.push({
    name: 'ProxyAdmin',
    address: proxyAdminAddress,
  });

  const insuranceFundAddress = await read('ClearingHouse', 'insuranceFund');
  console.log('InsuranceFund : ', insuranceFundAddress);
  await save('InsuranceFund', { abi: InsuranceFund__factory.abi, address: insuranceFundAddress });

  await hre.tenderly.push({
    name: 'TransparentUpgradeableProxy',
    address: insuranceFundAddress,
  });
};

export default func;

func.tags = ['RageTradeFactory'];
