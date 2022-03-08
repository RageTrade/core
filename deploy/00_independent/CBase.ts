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

  const { cBaseAddress } = getNetworkInfo(hre.network.config.chainId);

  if (cBaseAddress === undefined) {
    const deployment = await deploy('CBase', {
      contract: 'CBaseMock',
      from: deployer,
      log: true,
    });

    await execute('RBase', { from: deployer }, 'mint', deployer, hre.ethers.BigNumber.from(10).pow(8));

    if (deployment.newlyDeployed) {
      await hre.tenderly.push({
        name: 'CBaseMock',
        address: deployment.address,
      });
    }
  } else {
    await save('CBase', { abi: IERC20Metadata__factory.abi, address: cBaseAddress });
  }
};

export default func;

func.tags = ['CBase'];
