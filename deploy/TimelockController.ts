import { isAddress } from 'ethers/lib/utils';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { getNetworkInfo, waitConfirmations } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, execute, read },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const { governanceContract, timelockMinDelay } = getNetworkInfo(hre.network.config.chainId);

  await deploy('TimelockController', {
    contract: 'TimelockControllerWithMinDelayOverride',
    from: deployer,
    log: true,
    args: [timelockMinDelay ?? 2 * 24 * 3600, [], []],
    waitConfirmations,
  });

  if (governanceContract && isAddress(governanceContract)) {
    const TIMELOCK_ADMIN_ROLE = await read('TimelockController', 'TIMELOCK_ADMIN_ROLE');

    // make the governance contract the admin of Timelock
    await execute('TimelockController', { from: deployer }, 'grantRole', TIMELOCK_ADMIN_ROLE, governanceContract);

    // renounce admin control from deployer
    await execute('TimelockController', { from: deployer }, 'renounceRole', TIMELOCK_ADMIN_ROLE, deployer);
  }
};

export default func;

func.tags = ['TimelockController'];
