import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
    network,
  } = hre;

  const { deployer } = await getNamedAccounts();

  await deploy('NativeOracle', {
    contract: 'OracleMock',
    from: deployer,
    log: true,
  });
};

export default func;

func.tags = ['NativeOracle'];
