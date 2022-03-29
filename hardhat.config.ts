import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@protodev-rage/hardhat-tenderly';
import '@typechain/hardhat';
import { config } from 'dotenv';
import { ethers } from 'ethers';
import { task } from 'hardhat/config';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import 'hardhat-tracer';
import 'solidity-coverage';

config();
const { ALCHEMY_KEY } = process.env;

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

if (!process.env.ALCHEMY_KEY) {
  console.warn('PLEASE NOTE: The env var ALCHEMY_KEY is not set');
}

const pk = process.env.PRIVATE_KEY || ethers.utils.hexlify(ethers.utils.randomBytes(32));

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  networks: {
    hardhat: {
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true,
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`,
        blockNumber: 13075000,
      },
    },
    localhost: {
      url: 'http://localhost:8545',
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
    arbmain: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
    arbtest: {
      url: `https://rinkeby.arbitrum.io/rpc`,
      accounts: [pk],
      chainId: 421611,
    },
    optest: {
      url: `https://opt-kovan.g.alchemy.com/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
      chainId: 69,
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.13',
        settings: {
          optimizer: {
            enabled: true,
            runs: 833,
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
    alwaysGenerateOverloads: false,
    externalArtifacts: [
      'node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json',
      'node_modules/@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3PoolDeployer.sol/IUniswapV3PoolDeployer.json',
    ],
  },
  etherscan: {
    // https://info.etherscan.com/api-keys/
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
  contractSizer: {
    strict: true,
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  tenderly: {
    project: process.env.TENDERLY_PROJECT,
    username: process.env.TENDERLY_USERNAME,
  },
};
