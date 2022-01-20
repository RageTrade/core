import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const deployment = await deploy('InsuranceFundLogic', {
    contract: 'InsuranceFund',
    from: deployer,
    log: true,
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.verify({
      name: 'InsuranceFund',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['InsuranceFundLogic'];
