import hre from "hardhat"
// import deployments from "../deployments/rinkeby/"
import deployments from "../deployments/arbtest"

import {
  getContractsWithDeployments,
  formatUsdc,
  truncate
} from "@ragetrade/sdk"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

let value, post;

async function test() {
  const deployer: SignerWithAddress = await hre.ethers.getSigner('0x4ec0dda0430a54b4796109913545f715b2d89f34')

  const contracts = await getContractsWithDeployments(deployer, {
    AccountLibraryDeployment: {
      address: deployments.AccountLibrary.address
    },
    ClearingHouseDeployment: {
      address: deployments.ClearingHouse.address
    },
    ClearingHouseLogicDeployment: {
      address: deployments.ClearingHouseLogic.address
    },
    InsuranceFundDeployment: {
      address: deployments.InsuranceFund.address
    },
    InsuranceFundLogicDeployment: {
      address: deployments.InsuranceFundLogic.address
    },
    NativeOracleDeployment: {
      address: deployments.NativeOracle.address
    },
    ProxyAdminDeployment: {
      address: deployments.ProxyAdmin.address
    },
    RageTradeFactoryDeployment: {
      address: deployments.RageTradeFactory.address
    },
    RBaseDeployment: {
      address: deployments.RBase.address
    },
    VBaseDeployment: {
      address: deployments.VBase.address
    },
    VPoolWrapperLogicDeployment: {
      address: deployments.VPoolWrapperLogic.address
    },
    SwapSimulatorDeployment: {
      address: deployments.SwapSimulator.address
    },
    ETH_vTokenDeployment: {
      address: deployments.ETH_vToken.address
    },
    ETH_vPoolDeployment: {
      address: deployments.ETH_vPool.address
    },
    ETH_vPoolWrapperDeployment: {
      address: deployments.ETH_vPoolWrapper.address
    },
    ETH_IndexOracleDeployment: {
      address: deployments.ETH_IndexOracle.address
    },
  })

  const { clearingHouse, rBase, eth_vToken, eth_vPool } = contracts;

  // const usdc = await hre.ethers.getContractAt("RealBaseMock", deployments.RBase.address)
  // await usdc.mint(deployer.address, 10n ** 20n)

  const accountNo = await clearingHouse.callStatic.createAccount()
  const tx0 = await (await clearingHouse.createAccount()).wait()
  console.log('account created')
  console.log('account #', accountNo)

  const balance = await rBase.balanceOf(deployer.address);
  console.log('formatted rbase bal : ', formatUsdc(balance));

  const amount = hre.ethers.BigNumber.from(10).pow(15)
  const tx1 = await (await rBase.approve(clearingHouse.address, amount)).wait();
  console.log('approved successfully')

  const tx2 = await (await clearingHouse.addMargin(
    accountNo,
    truncate(rBase.address),
    amount
  )).wait();
  console.log('margin added successfully')

  // const tx3 = await (await clearingHouse.updateRangeOrder(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     tickLower: -197260,
  //     tickUpper: -197060,
  //     liquidityDelta: 105727785709044000n,
  //     sqrtPriceCurrent: '0',
  //     slippageToleranceBps: 10000,
  //     closeTokenPosition: false,
  //     limitOrderType: 0,
  //   })).wait()
  // console.log('updated range order #1 successfully')

  // const tx4 = await (await clearingHouse.updateRangeOrder(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     tickLower: -197550,
  //     tickUpper: -196570,
  //     liquidityDelta: 18032713203189600n,
  //     sqrtPriceCurrent: '0',
  //     slippageToleranceBps: 10000,
  //     closeTokenPosition: false,
  //     limitOrderType: 0,
  //   })).wait()
  // console.log('updated range order #2 successfully')

  // value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  // value = ((value ** 2n) * 10n ** 30n) >> 192n
  // console.log("price #1 : ", value)

  // const tx5 = await (await clearingHouse.swapToken(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     amount: 10n ** 19n,
  //     sqrtPriceLimit: 0,
  //     isNotional: false,
  //     isPartialAllowed: false
  //   }
  // )).wait()
  // console.log('swapped #1 successfully')

  // post = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  // post = ((post ** 2n) * 10n ** 30n) >> 192n
  // console.log("price #2 : ", post)

  // const tx6 = await (await clearingHouse.swapToken(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     amount: 2n * (10n ** 18n),
  //     sqrtPriceLimit: 0,
  //     isNotional: false,
  //     isPartialAllowed: false
  //   }
  // )).wait()
  // console.log('swapped #2 successfully')

  // post = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()

  // post = ((post ** 2n) * 10n ** 30n) >> 192n
  // console.log("price #3 : ", post)

  // value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  // value = ((value ** 2n) * 10n ** 30n) >> 192n
  // console.log("price #3 : ", value)

  // const tx7 = await (await clearingHouse.swapToken(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     amount: -5n * (10n ** 18n),
  //     sqrtPriceLimit: 0,
  //     isNotional: false,
  //     isPartialAllowed: false
  //   }
  // )).wait()
  // console.log('swapped #3 successfully')

  // post = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()

  // post = ((post ** 2n) * 10n ** 30n) >> 192n
  // console.log("price #4 : ", post)

  // const tx3 = await (await clearingHouse.updateRangeOrder(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     tickLower: -197320,
  //     tickUpper: -197120,
  //     liquidityDelta: 111958688882353000n,
  //     sqrtPriceCurrent: '0',
  //     slippageToleranceBps: 10000,
  //     closeTokenPosition: false,
  //     limitOrderType: 0,
  //   })).wait()
  // console.log('updated range order #1 successfully')

  // const tx4 = await (await clearingHouse.updateRangeOrder(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     tickLower: -197710,
  //     tickUpper: -196730,
  //     liquidityDelta: 21861315842714600n,
  //     sqrtPriceCurrent: '0',
  //     slippageToleranceBps: 10000,
  //     closeTokenPosition: false,
  //     limitOrderType: 0,
  //   })).wait()
  // console.log('updated range order #2 successfully')

  // const tx5 = await (await clearingHouse.updateRangeOrder(
  //   accountNo,
  //   truncate(eth_vToken.address),
  //   {
  //     tickLower: -198170,
  //     tickUpper: -196270,
  //     liquidityDelta: 11331643625720400n,
  //     sqrtPriceCurrent: '0',
  //     slippageToleranceBps: 10000,
  //     closeTokenPosition: false,
  //     limitOrderType: 0,
  //   })).wait()
  // console.log('updated range order #3 successfully')

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #1 : ", value)

  const tx7 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: 10n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #1 successfully')
  console.log(tx7.transactionHash)

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #2 : ", value)

  const tx8 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: -10n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #2 successfully')

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #3 : ", value)

  const tx9 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: 20n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #3 successfully')
  console.log(tx9.transactionHash)

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #4 : ", value)

  const tx10 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: -20n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #4 successfully')

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #5 : ", value)

  const tx11 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: 28n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #5 successfully')
  console.log(tx11.transactionHash)

  value = (await eth_vPool.slot0()).sqrtPriceX96.toBigInt()
  value = ((value ** 2n) * 10n ** 30n) >> 192n
  console.log("price #6 : ", value)

  const tx12 = await (await clearingHouse.swapToken(
    accountNo,
    truncate(eth_vToken.address),
    {
      amount: -28n * (10n ** 18n),
      sqrtPriceLimit: 0,
      isNotional: false,
      isPartialAllowed: false
    }
  )).wait()
  console.log('swapped #6 successfully')

}

test()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
