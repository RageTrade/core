import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getNetworkInfo } from '../network-info';
import { IERC20Metadata__factory } from '../../typechain-types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, save },
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

    if (deployment.newlyDeployed) {
      await hre.tenderly.verify({
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
