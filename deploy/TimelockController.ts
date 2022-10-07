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

  const { multisigAddress, timelockMinDelay } = getNetworkInfo();

  const isMultisigAddressProvided = multisigAddress && isAddress(multisigAddress);
  if (isMultisigAddressProvided) {
    console.log('Multisig address provided', multisigAddress);
  } else {
    console.log('Multisig address not provided');
  }

  const proposers = isMultisigAddressProvided ? [multisigAddress] : [];
  const executors = isMultisigAddressProvided ? [multisigAddress] : [];

  await deploy('TimelockController', {
    contract: 'TimelockControllerWithMinDelayOverride',
    from: deployer,
    log: true,
    args: [timelockMinDelay ?? 2 * 24 * 3600, proposers, executors],
    waitConfirmations,
  });

  if (isMultisigAddressProvided && multisigAddress.toLowerCase() !== deployer.toLowerCase()) {
    const TIMELOCK_ADMIN_ROLE = await read('TimelockController', 'TIMELOCK_ADMIN_ROLE');

    // make the governance contract the admin of Timelock
    await execute(
      'TimelockController',
      { from: deployer, log: true },
      'grantRole',
      TIMELOCK_ADMIN_ROLE,
      multisigAddress,
    );

    // renounce admin control from deployer
    await execute('TimelockController', { from: deployer, log: true }, 'renounceRole', TIMELOCK_ADMIN_ROLE, deployer);
  }
};

export default func;

func.tags = ['TimelockController'];
