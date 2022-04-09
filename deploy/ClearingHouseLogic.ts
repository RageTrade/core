import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { getNetworkInfo } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();
  const accountLibrary = await get('AccountLibrary');
  const { clearingHouseContractName } = getNetworkInfo(hre.network.config.chainId);

  const deployment = await deploy('ClearingHouseLogic', {
    contract: clearingHouseContractName,
    from: deployer,
    log: true,
    libraries: {
      Account: accountLibrary.address,
    },
  });

  if (deployment.newlyDeployed && hre.network.config.chainId !== 31337) {
    await hre.tenderly.push({
      name: clearingHouseContractName,
      address: deployment.address,
      libraries: {
        Account: accountLibrary.address,
      },
    });
  }
};

export default func;

func.tags = ['ClearingHouseLogic'];
func.dependencies = ['AccountLibrary'];
