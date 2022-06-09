import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { getNetworkInfo, waitConfirmations } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();
  const accountLibrary = await get('AccountLibrary');

  await deploy('ClearingHouseLogic', {
    contract: 'ClearingHouse',
    from: deployer,
    log: true,
    libraries: {
      Account: accountLibrary.address,
    },
    waitConfirmations,
  });
};

export default func;

func.tags = ['ClearingHouseLogic'];
func.dependencies = ['AccountLibrary'];
