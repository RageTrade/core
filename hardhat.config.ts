import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@protodev-rage/hardhat-tenderly';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import 'hardhat-tracer';
import 'solidity-coverage';

import { config } from 'dotenv';
import { ethers } from 'ethers';
import { Fragment } from 'ethers/lib/utils';
import { readJsonSync, writeJsonSync } from 'fs-extra';
import { TASK_COMPILE } from 'hardhat/builtin-tasks/task-names';
import { task } from 'hardhat/config';
import nodePath from 'path';

// this compile task override is needed to copy missing abi fragments to respective artifacts (note its not aval to typechain)
task(TASK_COMPILE, 'Compiles the entire project, building all artifacts').setAction(async (taskArgs, _, runSuper) => {
  const compileSolOutput = await runSuper(taskArgs);

  copyEventErrorAbis(
    [
      'artifacts/contracts/libraries/Account.sol/Account.json',
      'artifacts/contracts/libraries/CollateralDeposit.sol/CollateralDeposit.json',
      'artifacts/contracts/libraries/LiquidityPosition.sol/LiquidityPosition.json',
      'artifacts/contracts/libraries/LiquidityPositionSet.sol/LiquidityPositionSet.json',
      'artifacts/contracts/libraries/VTokenPosition.sol/VTokenPosition.json',
      'artifacts/contracts/libraries/VTokenPositionSet.sol/VTokenPositionSet.json',
    ],
    'artifacts/contracts/protocol/clearinghouse/ClearingHouse.sol/ClearingHouse.json',
  );

  copyEventErrorAbis(
    [
      'artifacts/contracts/libraries/AddressHelper.sol/AddressHelper.json',
      'artifacts/contracts/libraries/FundingPayment.sol/FundingPayment.json',
      'artifacts/contracts/libraries/SimulateSwap.sol/SimulateSwap.json',
      'artifacts/contracts/libraries/PriceMath.sol/PriceMath.json',
      'artifacts/contracts/libraries/SafeCast.sol/SafeCast.json',
      'artifacts/contracts/libraries/UniswapV3PoolHelper.sol/UniswapV3PoolHelper.json',
      'artifacts/@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol/TickMath.json',
    ],
    'artifacts/contracts/protocol/wrapper/VPoolWrapper.sol/VPoolWrapper.json',
  );

  function copyEventErrorAbis(froms: string[], to: string) {
    for (const from of froms) {
      copyEventErrorAbi(from, to);
    }
  }

  function copyEventErrorAbi(from: string, to: string) {
    const fromArtifact = readJsonSync(nodePath.resolve(__dirname, from));
    const toArtifact = readJsonSync(nodePath.resolve(__dirname, to));
    fromArtifact.abi.forEach((fromFragment: Fragment) => {
      if (
        // only copy error and event fragments
        (fromFragment.type === 'error' || fromFragment.type === 'event') &&
        // if fragment is already in the toArtifact, don't copy it
        !toArtifact.abi.find(
          ({ name, type }: Fragment) => name + '-' + type === fromFragment.name + '-' + fromFragment.type,
        )
      ) {
        toArtifact.abi.push(fromFragment);
      }
    });

    writeJsonSync(nodePath.resolve(__dirname, to), toArtifact, { spaces: 2 });
  }

  return compileSolOutput;
});

config();
const {
  ALCHEMY_KEY,
  ETHERSCAN_KEY,
  PRIVATE_KEY,
  REPORT_GAS,
  COINMARKETCAP,
  LEDGER_ADDRESS,
  TENDERLY_PROJECT,
  TENDERLY_USERNAME,
} = process.env;
if (!ALCHEMY_KEY) {
  console.warn('PLEASE NOTE: The env var ALCHEMY_KEY is not set');
}

const pk = PRIVATE_KEY || ethers.utils.hexlify(ethers.utils.randomBytes(32));

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
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [pk],
    },
    arbmain: {
      url: `https://arb1.arbitrum.io/rpc`,
      accounts: [pk],
      chainId: 42161,
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
        version: '0.8.14',
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 4999,
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
  dependencyCompiler: {
    paths: [
      '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
      '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
    ],
  },
  etherscan: {
    // https://info.etherscan.com/api-keys/
    apiKey: ETHERSCAN_KEY,
  },
  mocha: {
    timeout: 100000,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    enabled: !!REPORT_GAS, // REPORT_GAS=true yarn test
    coinmarketcap: COINMARKETCAP, // https://coinmarketcap.com/api/pricing/
  },
  contractSizer: {
    strict: true,
    except: ['contracts/test/*', 'console.sol'],
  },
  namedAccounts: {
    deployer: LEDGER_ADDRESS
      ? `ledger://${LEDGER_ADDRESS}`
      : {
          default: 0,
        },
  },
  tenderly: {
    project: TENDERLY_PROJECT,
    username: TENDERLY_USERNAME,
  },
};
