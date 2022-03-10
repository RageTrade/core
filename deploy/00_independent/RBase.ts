import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from '../network-info';
import { IERC20Metadata__factory } from '../../typechain-types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, save, execute },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const { rBaseAddress } = getNetworkInfo(hre.network.config.chainId);

  if (rBaseAddress === undefined) {
    const deployment = await deploy('RBase', {
      contract: 'RealBaseMock',
      from: deployer,
      log: true,
    });

    await execute('RBase', { from: deployer }, 'mint', deployer, hre.ethers.BigNumber.from(10).pow(8));

    if (deployment.newlyDeployed) {
      await hre.tenderly.push({
        name: 'RealBaseMock',
        address: deployment.address,
      });
    }
  } else {
    await save('RBase', { abi: IERC20Metadata__factory.abi, address: rBaseAddress });
  }
};

export default func;

func.tags = ['RBase'];
