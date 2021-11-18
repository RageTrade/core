import { config } from 'dotenv';
import { task } from 'hardhat/config';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-tracer';
import '@typechain/hardhat';
import 'hardhat-gas-reporter';
import 'hardhat-deploy';
import '@nomiclabs/hardhat-etherscan';

import { ethers } from 'ethers';
config();
const { MNEMONIC, ALCHEMY_KEY } = process.env;
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

if (!process.env.ALCHEMY_KEY) {
  console.warn('PLEASE NOTE: The env var ALCHEMY_KEY is not set');
}

const pk = process.env.PRIVATE_KEY || ethers.utils.hexlify(ethers.utils.randomBytes(32));

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  networks: {
    hardhat: {
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      accounts: { mnemonic: MNEMONIC },
      allowUnlimitedContractSize: true, // TODO: remove this
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
    arbitrumRinkeby: {
      url: `https://arb-rinkeby.g.alchemy.com/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.9',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
    ],
  },
  typechain: {
    target: 'ethers-v5',
    alwaysGenerateOverloads: false, // should overloads with full signatures like deposit(uint256) be generated always, even if there are no overloads?
    externalArtifacts: [
      'node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json',
      'node_modules/@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3PoolDeployer.sol/IUniswapV3PoolDeployer.json',
    ], // optional array of glob patterns with external artifacts to process (for example external libs from node_modules)
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_KEY,
  },
  mocha: {
    timeout: 100000,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    enabled: !!process.env.REPORT_GAS, // REPORT_GAS=true yarn test
    coinmarketcap: process.env.COINMARKETCAP, // https://coinmarketcap.com/api/pricing/
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
};
