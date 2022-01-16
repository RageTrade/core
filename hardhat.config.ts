import { config } from 'dotenv';
import { task } from 'hardhat/config';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-tracer';
import '@typechain/hardhat';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'solidity-coverage';
import '@nomiclabs/hardhat-etherscan';
import { ethers } from 'ethers';

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
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          metadata: {
            // do not include the metadata hash, since this is machine dependent
            // and we want all generated code to be deterministic
            // https://docs.soliditylang.org/en/v0.8.10/metadata.html
            bytecodeHash: 'none',
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
          metadata: {
            // do not include the metadata hash, since this is machine dependent
            // and we want all generated code to be deterministic
            // https://docs.soliditylang.org/en/v0.7.6/metadata.html
            bytecodeHash: 'none',
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
};
