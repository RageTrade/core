import { config } from 'dotenv';
import { network } from 'hardhat';

config();
const { ALCHEMY_KEY } = process.env;

interface MainnetForkOptions {
  blockNumber?: number;
  network?: 'mainnet' | 'arbitrum-mainnet';
}

export async function activateMainnetFork(options?: MainnetForkOptions) {
  if (!options) options = {};

  if (options.network === undefined) options.network = 'mainnet';

  if (options.blockNumber === undefined) {
    switch (options.network) {
      case 'mainnet':
        options.blockNumber = 13075000;
        break;
      case 'arbitrum-mainnet':
        options.blockNumber = 4454178;
        break;
      default:
        throw new Error('Incorrect network');
    }
  }

  let jsonRpcUrl: string;

  switch (options.network) {
    case 'mainnet':
      jsonRpcUrl = 'https://eth-mainnet.alchemyapi.io/v2/' + ALCHEMY_KEY;
      break;
    case 'arbitrum-mainnet':
      jsonRpcUrl = 'https://arb-mainnet.g.alchemy.com/v2/' + ALCHEMY_KEY;
      break;
    default:
      throw new Error('Incorrect network');
  }

  await network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl,
          blockNumber: options.blockNumber,
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
