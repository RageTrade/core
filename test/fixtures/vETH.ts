import { formatUnits, parseUnits } from 'ethers/lib/utils';
import { deployments } from 'hardhat';

import { priceToTick, sqrtPriceX96ToPrice, tickToNearestInitializableTick, truncate } from '@ragetrade/sdk';

export const vEthFixture = deployments.createFixture(async hre => {
  const rageTradeDeployments = await deployments.fixture('vETH');

  // global contracts
  const rageTradeFactory = await hre.ethers.getContractAt(
    'RageTradeFactory',
    rageTradeDeployments.RageTradeFactory.address,
  );
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouseTest', rageTradeDeployments.ClearingHouse.address);
  const proxyAdmin = await hre.ethers.getContractAt('ProxyAdmin', await rageTradeFactory.proxyAdmin());
  const cht = await (
    await hre.ethers.getContractFactory('ClearingHouseTest', {
      libraries: {
        Account: rageTradeDeployments.AccountLibrary.address,
      },
    })
  ).deploy();
  await proxyAdmin.upgrade(clearingHouse.address, cht.address);

  // @ts-ignore
  hre.tracer.nameTags['ClearingHouse'] = clearingHouse.address;
  const settlementToken = await hre.ethers.getContractAt(
    'SettlementTokenMock',
    rageTradeDeployments.SettlementToken.address,
  );

  // vETH pool
  const vToken = await hre.ethers.getContractAt('VToken', rageTradeDeployments['ETH-vToken'].address);
  const vPool = await hre.ethers.getContractAt('IUniswapV3Pool', rageTradeDeployments['ETH-vPool'].address);
  const vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', rageTradeDeployments['ETH-vPoolWrapper'].address);
  const oracle = await hre.ethers.getContractAt('IOracle', rageTradeDeployments['ETH-IndexOracle'].address);

  // create admin account
  await clearingHouse.createAccount();
  const account0 = 0;

  // add margin
  const poolId = truncate(vToken.address);
  const [signer] = await hre.ethers.getSigners();
  const depositAmount = parseUnits('1000000000', 6);
  await settlementToken.mint(signer.address, depositAmount);
  await settlementToken.transfer(rageTradeDeployments.InsuranceFund.address, depositAmount);

  await settlementToken.mint(signer.address, depositAmount);
  await settlementToken.approve(clearingHouse.address, depositAmount);
  await clearingHouse.updateMargin(account0, truncate(settlementToken.address), depositAmount);

  // add liquidity
  await clearingHouse.updateRangeOrder(account0, poolId, {
    tickLower: tickToNearestInitializableTick(await priceToTick(100, 6, 18)),
    tickUpper: tickToNearestInitializableTick(await priceToTick(100000, 6, 18)),
    liquidityDelta: '100000000000000000',
    sqrtPriceCurrent: 0,
    slippageToleranceBps: 0,
    closeTokenPosition: false,
    limitOrderType: 0,
    settleProfit: false,
  });

  // create user account
  await clearingHouse.createAccount();
  const account1 = 1;

  await settlementToken.mint(signer.address, depositAmount);
  await settlementToken.approve(clearingHouse.address, depositAmount);

  return {
    rageTradeFactory,
    rageTradeDeployments,
    clearingHouse,
    settlementToken,
    vToken,
    vPool,
    vPoolWrapper,
    oracle,
    account0,
    account1,
    poolId,
    printMarketVal,
  };

  async function printMarketVal() {
    const { marketValue, requiredMargin } = await clearingHouse.getAccountMarketValueAndRequiredMargin(account1, false);

    const { sqrtPriceX96 } = await vPool.slot0();
    const price = await sqrtPriceX96ToPrice(sqrtPriceX96, 6, 18);
    console.log(
      'market value',
      formatUnits(marketValue, 6),
      'required margin',
      formatUnits(requiredMargin, 6),
      'price',
      price,
    );
  }
});
