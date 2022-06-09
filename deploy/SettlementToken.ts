import { parseUsdc } from '@ragetrade/sdk';
import { parseUnits } from 'ethers/lib/utils';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import { IERC20Metadata__factory } from '../typechain-types';
import { getNetworkInfo, waitConfirmations } from './network-info';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, save, execute },
    getNamedAccounts,
  } = hre;

  const { deployer } = await getNamedAccounts();

  const { SETTLEMENT_TOKEN_ADDRESS } = getNetworkInfo(hre.network.config.chainId);

  // if SETTLEMENT_TOKEN_ADDRESS is not provided, then deploy a dummy ERC20 contract
  if (SETTLEMENT_TOKEN_ADDRESS === undefined) {
    await deploy('SettlementToken', {
      contract: 'SettlementTokenMock',
      from: deployer,
      log: true,
      waitConfirmations,
    });

    // mint dummy tokens to the deployer
    await execute(
      'SettlementToken',
      { from: deployer, waitConfirmations },
      'mint',
      deployer,
      parseUnits('1000000000', 6),
    );
  } else {
    await save('SettlementToken', { abi: IERC20Metadata__factory.abi, address: SETTLEMENT_TOKEN_ADDRESS });
  }
};

export default func;

func.tags = ['SettlementToken'];
