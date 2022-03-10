import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from '../network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const oracleAddr = getNetworkInfo(hre.network.config.chainId).ETH_USD_ORACLE;
  let deployment;

  if (oracleAddr) {
    deployment = await deploy('NativeOracle', {
      contract: 'ChainlinkOracle',
      args: [
        getNetworkInfo(hre.network.config.chainId).ETH_USD_ORACLE,
        '18', // native currency decimals
        '6', // base decimals
      ],
      from: deployer,
      log: true,
    });
  } else {
    deployment = await deploy('NativeOracle', {
      contract: 'OracleMock',
      from: deployer,
      log: true,
    });
  }

  if (deployment.newlyDeployed) {
    await hre.tenderly.push({
      name: 'ChainlinkOracle',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['NativeOracle'];
