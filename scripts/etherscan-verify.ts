import { ethers } from 'ethers';
import hre, { deployments, getNamedAccounts } from 'hardhat';
import { Deployment } from 'hardhat-deploy/types';

import { getNetworkInfo } from '../deploy/network-info';
import { ClearingHouse__factory, VPoolWrapper__factory } from '../typechain-types';

async function main() {
  const { get } = deployments;

  const accountLibrary = await hreVerify('AccountLibrary');
  const clearingHouseLogic = await hreVerify('ClearingHouseLogic', {
    libraries: {
      Account: accountLibrary.address,
    },
  });
  const vPoolWrapperLogic = await hreVerify('VPoolWrapperLogic');
  const insuranceFundLogic = await hreVerify('InsuranceFundLogic');
  const settlementToken = await hreVerify('SettlementToken');
  const settlementTokenOracle = await hreVerify('SettlementTokenOracle');
  const rageTradeFactory = await hreVerify('RageTradeFactory', {
    constructorArguments: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      settlementToken.address,
      settlementTokenOracle.address,
    ],
  });

  const proxyAdmin = await hreVerify('ProxyAdmin');
  const vQuote = await hreVerify('VQuote', { constructorArguments: [6] });
  const insuranceFund = await hreVerify('InsuranceFund', {
    constructorArguments: [insuranceFundLogic.address, proxyAdmin.address, '0x'],
  });

  const { deployer } = await getNamedAccounts();
  const chInitializeData = ClearingHouse__factory.createInterface().encodeFunctionData('initialize', [
    rageTradeFactory.address,
    deployer,
    deployer,
    settlementToken.address,
    settlementTokenOracle.address,
    insuranceFund.address,
    vQuote.address,
  ]);
  const clearingHouse = await hreVerify('ClearingHouse', {
    constructorArguments: [clearingHouseLogic.address, proxyAdmin.address, chInitializeData],
  });
  await hreVerify('ClearingHouseLens', { constructorArguments: [clearingHouse.address] });

  const { CHAINLINK_ETH_USD_ORACLE, FLAGS_INTERFACE } = getNetworkInfo(hre.network.config.chainId);
  await hreVerify('ETH-IndexOracle', {
    constructorArguments: [CHAINLINK_ETH_USD_ORACLE, FLAGS_INTERFACE ?? ethers.constants.AddressZero, 18, 6],
  });
  const ethVPool = await hreVerify('ETH-vPool');
  const ethVToken = await hreVerify('ETH-vToken', { constructorArguments: ['Virtual Ether (Rage Trade)', 'vETH', 18] });
  await hreVerify('ETH-vPoolWrapper', {
    constructorArguments: [
      vPoolWrapperLogic.address,
      proxyAdmin.address,
      VPoolWrapper__factory.createInterface().encodeFunctionData('initialize', [
        {
          clearingHouse: clearingHouse.address,
          vToken: ethVToken.address,
          vQuote: vQuote.address,
          vPool: ethVPool.address,
          liquidityFeePips: 1000,
          protocolFeePips: 500,
        },
      ]),
    ],
  });

  await hreVerify('SwapSimulator');

  const { multisigAddress, timelockMinDelay } = getNetworkInfo(hre.network.config.chainId);
  const proposers = multisigAddress ? [multisigAddress] : [];
  const executors = multisigAddress ? [multisigAddress] : [];
  await hreVerify('TimelockController', {
    constructorArguments: [timelockMinDelay ?? 172800, proposers, executors],
  });

  // helper method that verify a contract and returns the deployment
  async function hreVerify(label: string, taskArguments: any = {}): Promise<Deployment> {
    console.log('verifying:', label);

    const deployment = await get(label);
    taskArguments = { address: deployment.address, ...taskArguments };

    // try to verify on etherscan
    try {
      await hre.run('verify:verify', taskArguments);
    } catch (err: any) {
      console.log(err);
    }
    return deployment;
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
