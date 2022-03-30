import hre, { ethers } from 'hardhat';
import { FakeContract, smock } from '@defi-wonderland/smock';
import { ClearingHouse, ERC20, VQuote, RageTradeFactory } from '../../typechain-types';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  SETTLEMENT_TOKEN,
} from './realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from './create-addresses';
// import { ConstantsStruct } from '../../typechain-types/ClearingHouse';

export async function testSetup({
  signer,
  initialMarginRatioBps,
  maintainanceMarginRatioBps,
  twapDuration,
  whitelisted,
}: {
  signer?: SignerWithAddress;
  initialMarginRatioBps: number;
  maintainanceMarginRatioBps: number;
  twapDuration: number;
  whitelisted: boolean;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //SettlementToken
  const settlementToken = await smock.fake<ERC20>('ERC20');
  settlementToken.decimals.returns(6);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
      libraries: {
        Account: accountLib.address,
      },
    })
  ).deploy();

  const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

  const insuranceFundLogic = await (await hre.ethers.getContractFactory('InsuranceFund')).deploy();

  const nativeOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  const rageTradeFactory = await (
    await hre.ethers.getContractFactory('RageTradeFactory')
  ).deploy(clearingHouseLogic.address, vPoolWrapperLogic.address, insuranceFundLogic.address, settlementToken.address);

  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());

  const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());

  //VQuote
  const vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20', { address: ethers.constants.AddressZero });
  realToken.decimals.returns(18);

  // const vPoolWrapperDeployer = await (
  //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  // ).deploy(futureVPoolFactoryAddress);

  // const vPoolFactory = await (
  //   await hre.ethers.getContractFactory('VPoolFactory')
  // ).deploy(
  //   vQuote.address,
  //   clearingHouse.address,
  //   vPoolWrapperDeployer.address,
  //   UNISWAP_FACTORY_ADDRESS,
  //   DEFAULT_FEE_TIER,
  //   UNISWAP_V3_POOL_BYTE_CODE_HASH,
  // );

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vTest',
      vTokenSymbol: 'vTest',
      cTokenDecimals: 18,
    },
    poolInitialSettings: {
      initialMarginRatioBps,
      maintainanceMarginRatioBps,
      maxVirtualPriceDeviationRatioBps: 10000,
      twapDuration,
      isAllowedForTrade: false,
      isCrossMargined: false,
      oracle: oracle.address,
    },
    liquidityFeePips: 500,
    protocolFeePips: 500,
    slotsToInitialize: 100,
  });

  const eventFilter = rageTradeFactory.filters.PoolInitialized();
  const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];
  // const constants = (await clearingHouse.getProtocolInfo()).constants;

  return {
    settlementToken,
    vQuote,
    oracle,
    clearingHouse,
    clearingHouseLogic,
    rageTradeFactory,
    vPoolAddress,
    vTokenAddress,
    vPoolWrapperAddress,
    insuranceFund,
    // constants,
  };
}

export async function testSetupVQuote(signer?: SignerWithAddress) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //SettlementToken
  const settlementToken = await smock.fake<ERC20>('ERC20');
  settlementToken.decimals.returns(6);

  //VQuote
  // const vQuote = await smock.fake<VQuote>('VQuote', { address: '0x8FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' });
  // vQuote.decimals.returns(6);

  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 3);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 4);

  // const vPoolWrapperDeployer = await (
  //   await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  // ).deploy(futureVPoolFactoryAddress);

  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
      libraries: {
        Account: accountLib.address,
      },
    })
  ).deploy();

  const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

  const insuranceFundLogic = await (await hre.ethers.getContractFactory('InsuranceFund')).deploy();

  const nativeOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  const rageTradeFactory = await (
    await hre.ethers.getContractFactory('RageTradeFactory')
  ).deploy(clearingHouseLogic.address, vPoolWrapperLogic.address, insuranceFundLogic.address, settlementToken.address);

  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());

  const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());

  const vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());
  // const constants = (await clearingHouse.getProtocolInfo()).constants;

  return {
    settlementToken,
    vQuote,
    clearingHouse,
    rageTradeFactory,
    insuranceFund,
    oracle,
  };
}

export async function testSetupToken({
  signer,
  decimals,
  initialMarginRatioBps,
  maintainanceMarginRatioBps,
  twapDuration,
  whitelisted,
  rageTradeFactory,
}: {
  signer?: SignerWithAddress;
  decimals: number;
  initialMarginRatioBps: number;
  maintainanceMarginRatioBps: number;
  twapDuration: number;
  whitelisted: boolean;
  rageTradeFactory: RageTradeFactory;
}) {
  signer = signer ?? (await hre.ethers.getSigners())[0];

  //Oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // ClearingHouse, VPoolFactory
  const realToken = await smock.fake<ERC20>('ERC20');
  realToken.decimals.returns(decimals);

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vTest',
      vTokenSymbol: 'vTest',
      cTokenDecimals: 18,
    },
    poolInitialSettings: {
      initialMarginRatioBps,
      maintainanceMarginRatioBps,
      maxVirtualPriceDeviationRatioBps: 10000,
      twapDuration,
      isAllowedForTrade: true,
      isCrossMargined: false,
      oracle: oracle.address,
    },
    liquidityFeePips: 500,
    protocolFeePips: 500,
    slotsToInitialize: 100,
  });
  const eventFilter = rageTradeFactory.filters.PoolInitialized();
  const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
  const vPoolAddress = events[0].args[0];
  const vTokenAddress = events[0].args[1];
  const vPoolWrapperAddress = events[0].args[2];

  return {
    oracle: oracle,
    vPoolAddress: vPoolAddress,
    vTokenAddress: vTokenAddress,
    vPoolWrapperAddress: vPoolWrapperAddress,
  };
}
