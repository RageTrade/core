import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { IERC20Metadata__factory } from '../typechain-types';
import { getNetworkInfo } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, save, execute },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const { settlementTokenAddress } = getNetworkInfo(hre.network.config.chainId);

  if (settlementTokenAddress === undefined) {
    const deployment = await deploy('SettlementToken', {
      contract: 'SettlementTokenMock',
      from: deployer,
      log: true,
    });

    await execute('SettlementToken', { from: deployer }, 'mint', deployer, hre.ethers.BigNumber.from(10).pow(8));

    if (deployment.newlyDeployed && hre.network.config.chainId !== 31337) {
      await hre.tenderly.push({
        name: 'SettlementTokenMock',
        address: deployment.address,
      });
    }
  } else {
    await save('SettlementToken', { abi: IERC20Metadata__factory.abi, address: settlementTokenAddress });
  }
};

export default func;

func.tags = ['SettlementToken'];
