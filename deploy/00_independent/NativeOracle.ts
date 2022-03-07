import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from '../network-info'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, save },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  console.log('oracle', getNetworkInfo().ETH_USD_ORACLE)

  const deployment = await deploy('NativeOracle', {
    contract: 'ChainlinkOracle',
    // for rinkeby: 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e
    args: [
      '0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8',
      '18',
      '6'
    ],
    from: deployer,
    log: true,
    gasPrice: '0xd2d61a',
    gasLimit: 81279421
  });

  if (deployment.newlyDeployed) {
    await hre.tenderly.push({
      name: 'ChainlinkOracle',
      address: deployment.address,
    });
  }
};

export default func;

func.tags = ['NativeOracle'];
