import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
    network,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const deployment = await deploy('AccountLibrary', {
    contract: 'Account',
    from: deployer,
    log: true,
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.verify({
      name: 'Account',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['AccountLibrary'];
