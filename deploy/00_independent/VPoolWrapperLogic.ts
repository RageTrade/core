import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const deployment = await deploy('VPoolWrapperLogic', {
    contract: 'VPoolWrapper',
    from: deployer,
    log: true,
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.verify({
      name: 'VPoolWrapper',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['VPoolWrapperLogic'];
