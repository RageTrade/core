import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { config } from 'dotenv';

config();
const { ALCHEMY_KEY } = process.env;

export async function activateMainnetFork(hre: HardhatRuntimeEnvironment) {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl: 'https://eth-mainnet.alchemyapi.io/v2/' + ALCHEMY_KEY,
          blockNumber: 13075000,
        },
      },
    ],
  });
}

export async function deactivateMainnetFork(hre: HardhatRuntimeEnvironment) {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [{}],
  });
}
