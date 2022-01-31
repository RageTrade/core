import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
    network,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const deployment = await deploy('NativeOracle', {
    contract: 'OracleMock',
    from: deployer,
    log: true,
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.verify({
      name: 'OracleMock',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['NativeOracle'];
