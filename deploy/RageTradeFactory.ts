import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from './network-info';
import { ClearingHouse__factory, InsuranceFund__factory, VBase__factory } from '../typechain-types';

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

  const { UNISWAP_V3_FACTORY_ADDRESS, UNISWAP_V3_DEFAULT_FEE_TIER, UNISWAP_V3_POOL_BYTE_CODE_HASH } = getNetworkInfo(
    hre.network.config.chainId,
  );

  await deploy('RageTradeFactory', {
    from: deployer,
    log: true,
    args: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      rBase.address,
      rBase.address, // TODO change to native oracle
      UNISWAP_V3_FACTORY_ADDRESS,
      UNISWAP_V3_DEFAULT_FEE_TIER,
      UNISWAP_V3_POOL_BYTE_CODE_HASH,
    ],
  });

  const vBaseAddress = await read('RageTradeFactory', 'vBase');
  await save('VBase', { abi: VBase__factory.abi, address: vBaseAddress });

  const clearingHouseAddress = await read('RageTradeFactory', 'clearingHouse');
  await save('ClearingHouse', { abi: ClearingHouse__factory.abi, address: clearingHouseAddress });

  const insuranceFundAddress = await read('ClearingHouse', 'insuranceFund');
  await save('InsuranceFund', { abi: InsuranceFund__factory.abi, address: insuranceFundAddress });
};

export default func;

func.tags = ['RageTradeFactory'];
