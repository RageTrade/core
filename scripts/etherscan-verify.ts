import hre, { deployments } from 'hardhat';

import { ClearingHouse__factory, VPoolWrapper__factory } from '../typechain-types';

async function main() {
  const { get } = deployments;
  const accountLibrary = await get('AccountLibrary');
  const clearingHouseLogic = await get('ClearingHouseLogic');
  const vPoolWrapperLogic = await get('VPoolWrapperLogic');
  const insuranceFundLogic = await get('InsuranceFundLogic');
  const settlementToken = await get('SettlementToken');
  const rageTradeFactory = await get('RageTradeFactory');
  await hreVerify('AccountLibrary', { address: accountLibrary.address });
  await hreVerify('ClearingHouseLogic', {
    address: clearingHouseLogic.address,
    libraries: {
      Account: accountLibrary.address,
    },
  });
  await hreVerify('VPoolWrapperLogic', { address: vPoolWrapperLogic.address });
  await hreVerify('InsuranceFundLogic', { address: insuranceFundLogic.address });
  await hreVerify('SettlementToken', { address: settlementToken.address });
  await hreVerify('RageTradeFactory', {
    address: rageTradeFactory.address,
    constructorArguments: [
      clearingHouseLogic.address,
      vPoolWrapperLogic.address,
      insuranceFundLogic.address,
      settlementToken.address,
    ],
  });

  const vQuote = await get('VQuote');
  const clearingHouse = await get('ClearingHouse');
  const insuranceFund = await get('InsuranceFund');
  const proxyAdmin = await get('ProxyAdmin');
  const settlementTokenOracle = await get('SettlementTokenOracle');
  await hreVerify('VQuote', { address: vQuote.address, constructorArguments: [6] });
  const chInitializeData = ClearingHouse__factory.createInterface().encodeFunctionData('__initialize_ClearingHouse', [
    rageTradeFactory.address,
    settlementToken.address,
    settlementTokenOracle.address,
    insuranceFund.address,
    vQuote.address,
  ]);
  await hreVerify('ClearingHouse', {
    address: clearingHouse.address,
    constructorArguments: [clearingHouseLogic.address, proxyAdmin.address, chInitializeData],
  });
  await hreVerify('InsuranceFund', {
    address: insuranceFund.address,
    constructorArguments: [insuranceFundLogic.address, proxyAdmin.address, '0x'],
  });
  await hreVerify('ProxyAdmin', { address: proxyAdmin.address });

  const swapSimulator = await get('SwapSimulator');
  await hreVerify('SwapSimulator', { address: swapSimulator.address });

  const ethOracle = await get('ETH-IndexOracle');
  const ethVPool = await get('ETH-vPool');
  const ethVPoolWrapper = await get('ETH-vPoolWrapper');
  const ethVToken = await get('ETH-vToken');
  await hreVerify('ETH-IndexOracle', { address: ethOracle.address });
  await hreVerify('ETH-vPool', { address: ethVPool.address });
  const vpwData = VPoolWrapper__factory.createInterface().encodeFunctionData('__initialize_VPoolWrapper', [
    {
      clearingHouse: clearingHouse.address,
      vToken: ethVToken.address,
      vQuote: vQuote.address,
      vPool: ethVPool.address,
      liquidityFeePips: 1000,
      protocolFeePips: 500,
    },
  ]);
  await hreVerify('ETH-vPoolWrapper', {
    address: ethVPoolWrapper.address,
    constructorArguments: [vPoolWrapperLogic.address, proxyAdmin.address, vpwData],
  });
  await hreVerify('ETH-vToken', {
    address: ethVToken.address,
    constructorArguments: ['Virtual Ether (Rage Trade)', 'vETH', 18],
  });

  async function hreVerify(label: string, taskArguments: any) {
    console.log('verifying:', label);

    try {
      await hre.run('verify:verify', taskArguments);
    } catch (err: any) {
      console.log(err);
    }
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
