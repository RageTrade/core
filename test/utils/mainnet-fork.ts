import { network } from 'hardhat';
import { config } from 'dotenv';

config();
const { ALCHEMY_KEY } = process.env;

export async function activateMainnetFork(blockNumber?: number) {
  await network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl: 'https://eth-mainnet.alchemyapi.io/v2/' + ALCHEMY_KEY,
          blockNumber: blockNumber ?? 13075000,
        },
      },
    ],
  });
}

export async function deactivateMainnetFork() {
  await network.provider.request({
    method: 'hardhat_reset',
    params: [{}],
  });
}
