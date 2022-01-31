import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from './network-info';
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

  const { UNISWAP_V3_FACTORY_ADDRESS, UNISWAP_V3_DEFAULT_FEE_TIER, UNISWAP_V3_POOL_BYTE_CODE_HASH } = getNetworkInfo(
    hre.network.config.chainId,
  );

  const deployment = await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      rBase.address,
      nativeOracle.address,
      UNISWAP_V3_FACTORY_ADDRESS,
      UNISWAP_V3_DEFAULT_FEE_TIER,
      UNISWAP_V3_POOL_BYTE_CODE_HASH,
    ],
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.verify({
      name: 'RageTradeFactory',
      address: deployment.address,
    });
  }

  const vBaseAddress = await read('RageTradeFactory', 'vBase');
  await save('VBase', { abi: VBase__factory.abi, address: vBaseAddress });
  await hre.tenderly.verify({
    name: 'ProxyAdmin',
    address: vBaseAddress,
  });

  const clearingHouseAddress = await read('RageTradeFactory', 'clearingHouse');
  await save('ClearingHouse', { abi: ClearingHouse__factory.abi, address: clearingHouseAddress });
  await hre.tenderly.verify({
    name: 'TransparentUpgradeableProxy',
    address: clearingHouseAddress,
  });

  const proxyAdminAddress = await read('RageTradeFactory', 'proxyAdmin');
  await save('ProxyAdmin', { abi: ProxyAdmin__factory.abi, address: proxyAdminAddress });
  await hre.tenderly.verify({
    name: 'ProxyAdmin',
    address: proxyAdminAddress,
  });

  const insuranceFundAddress = await read('ClearingHouse', 'insuranceFund');
  await save('InsuranceFund', { abi: InsuranceFund__factory.abi, address: insuranceFundAddress });
  await hre.tenderly.verify({
    name: 'TransparentUpgradeableProxy',
    address: insuranceFundAddress,
  });
};

export default func;

func.tags = ['RageTradeFactory'];
