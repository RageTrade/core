import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  await deploy('VPoolWrapperLogic', {
    contract: 'VPoolWrapper',
    from: deployer,
    log: true,
  });
};

export default func;

func.tags = ['VPoolWrapperLogic'];
