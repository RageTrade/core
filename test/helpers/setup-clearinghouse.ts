import { BigNumberish, ethers } from 'ethers';
import { parseUnits } from 'ethers/lib/utils';
import hre from 'hardhat';

import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor, priceToSqrtPriceX96 } from '@ragetrade/sdk';

import { RageTradeFactory, RealTokenMock, SettlementTokenMock } from '../../typechain-types';
import { UNISWAP_V3_DEFAULT_FEE_TIER } from './realConstants';

interface SetupClearingHouseArgs {
  signer?: SignerWithAddress;
  vQuoteDecimals?: number;
  uniswapFeeTierDefault?: number;
  settlementTokenAddress?: string;
}

interface InitializePoolArgs {
  rageTradeFactory: RageTradeFactory;

  // initialize pool struct
  liquidityFeePips?: BigNumberish;
  protocolFeePips?: BigNumberish;

  // DeployVTokenParamsStructOutput
  vTokenName?: string;
  vTokenSymbol?: string;
  // cTokenAddress?: string;
  // oracleAddress?: string;
  vTokenDecimals?: number;

  // rage trade pool settings
  initialMarginRatioBps?: number;
  maintainanceMarginRatioBps?: number;
  twapDuration?: number;
  whitelisted?: boolean;
  // oracle: string;

  vPriceInitial?: number;
  rPriceInitial?: number;

  signer?: SignerWithAddress;
}

// sets up clearing house with upgradable logic
export async function setupClearingHouse({
  signer,
  vQuoteDecimals,
  uniswapFeeTierDefault,
  settlementTokenAddress,
}: SetupClearingHouseArgs) {
  vQuoteDecimals = vQuoteDecimals ?? 6;

  uniswapFeeTierDefault = uniswapFeeTierDefault ?? +UNISWAP_V3_DEFAULT_FEE_TIER;
  signer = signer ?? (await hre.ethers.getSigners())[0];

  // deploying settlement token
  let settlementToken: SettlementTokenMock;
  if (settlementTokenAddress) {
    settlementToken = await hre.ethers.getContractAt('SettlementTokenMock', settlementTokenAddress);
  } else {
    const _settlementToken = await (await hre.ethers.getContractFactory('SettlementTokenMock')).deploy();
    const d = await _settlementToken.decimals();
    await _settlementToken.mint(signer.address, parseUnits('100000', d));
    settlementToken = _settlementToken;
  }
  hre.tracer.nameTags[settlementToken.address] = 'settlementToken';

  // deploying main contracts
  const futureVPoolFactoryAddress = await getCreateAddressFor(signer, 5);
  const futureInsurnaceFundAddress = await getCreateAddressFor(signer, 6);

  // clearing house logic
  const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
  const clearingHouseLogic = await (
    await hre.ethers.getContractFactory('ClearingHouse', {
      libraries: {
        Account: accountLib.address,
      },
    })
  ).deploy();

  // proxy deployment
  // const proxyAdmin = await (await hre.ethers.getContractFactory('ProxyAdmin')).deploy();
  // const clearingHouseProxy = await (
  //   await hre.ethers.getContractFactory('TransparentUpgradeableProxy')
  // ).deploy(clearingHouseLogic.address, proxyAdmin.address, '0x');
  // const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', clearingHouseProxy.address);

  // wrapper
  const vPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapper')).deploy();

  const insuranceFundLogic = await (await hre.ethers.getContractFactory('InsuranceFund')).deploy();

  const nativeOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

  // rage trade factory
  const rageTradeFactory = await (
    await hre.ethers.getContractFactory('RageTradeFactory')
  ).deploy(clearingHouseLogic.address, vPoolWrapperLogic.address, insuranceFundLogic.address, settlementToken.address);

  // virtual quote
  const vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());
  hre.tracer.nameTags[vQuote.address] = 'vQuote';

  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());
  hre.tracer.nameTags[clearingHouse.address] = 'clearingHouse';

  const proxyAdmin = await hre.ethers.getContractAt('ProxyAdmin', await rageTradeFactory.proxyAdmin());
  hre.tracer.nameTags[proxyAdmin.address] = 'proxyAdmin';

  const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());
  hre.tracer.nameTags[insuranceFund.address] = 'insuranceFund';

  return {
    signer,
    settlementToken,
    vQuote,
    clearingHouse,
    proxyAdmin,
    clearingHouseLogic,
    accountLib,
    rageTradeFactory,
    insuranceFundLogic,
    insuranceFund,
  };
}

// TODO: finish this deployment setup
export async function initializePool({
  rageTradeFactory,

  liquidityFeePips,
  protocolFeePips,

  // DeployVTokenParamsStructOutput
  vTokenName,
  vTokenSymbol,

  vTokenDecimals,

  // rage trade pool settings
  initialMarginRatioBps,
  maintainanceMarginRatioBps,
  twapDuration,
  whitelisted,
  // oracle: string;

  vPriceInitial,
  rPriceInitial,

  signer,
}: InitializePoolArgs) {
  liquidityFeePips = liquidityFeePips ?? 1000;
  protocolFeePips = protocolFeePips ?? 500;
  vTokenName = vTokenName ?? 'vTokenName';
  vTokenSymbol = vTokenSymbol ?? 'vTokenSymbol';
  vTokenDecimals = vTokenDecimals ?? 18;

  initialMarginRatioBps = initialMarginRatioBps ?? 2000;
  maintainanceMarginRatioBps = maintainanceMarginRatioBps ?? 1000;
  twapDuration = twapDuration ?? 60;
  whitelisted = whitelisted ?? false;

  vPriceInitial = vPriceInitial ?? 1;
  rPriceInitial = rPriceInitial ?? 1;

  const vQuoteDecimalsDefault = 6;
  vTokenDecimals = vTokenDecimals ?? 18;

  const realToken = await smock.fake<RealTokenMock>('RealTokenMock');
  realToken.decimals.returns(vTokenDecimals);

  // oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
  await oracle.setSqrtPriceX96(await priceToSqrtPriceX96(rPriceInitial, vQuoteDecimalsDefault, vTokenDecimals));

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vWETH',
      vTokenSymbol: 'vWETH',
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
  const vPool = await hre.ethers.getContractAt(
    '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
    events[0].args[0],
  );
  const vToken = await hre.ethers.getContractAt('VToken', events[0].args[1]);
  const vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);
  return { vPool, vToken, vPoolWrapper, oracle };
}

export async function extractFromRageTradeFactory(rageTradeFactory: RageTradeFactory) {
  const vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());
  const proxyAdmin = await hre.ethers.getContractAt('ProxyAdmin', await rageTradeFactory.proxyAdmin());
  return { vQuote, clearingHouse, proxyAdmin };
}
