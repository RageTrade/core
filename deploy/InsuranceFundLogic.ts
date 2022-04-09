import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

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

  if (deployment.newlyDeployed && hre.network.config.chainId !== 31337) {
    await hre.tenderly.push({
      name: 'InsuranceFund',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['InsuranceFundLogic'];
