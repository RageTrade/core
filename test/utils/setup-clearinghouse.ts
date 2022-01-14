import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumberish, ethers } from 'ethers';
import { parseUnits } from 'ethers/lib/utils';
import hre from 'hardhat';
import { ClearingHouse, ERC20, VBase, RageTradeFactory, RealTokenMock } from '../../typechain-types';
import { InitializePoolParamsStruct } from '../../typechain-types/RageTradeFactory';
import { getCreateAddressFor } from './create-addresses';
import { priceToSqrtPriceX96 } from './price-tick';
import { randomAddress } from './random';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  UNISWAP_V3_DEFAULT_FEE_TIER,
} from './realConstants';

interface SetupClearingHouseArgs {
  signer?: SignerWithAddress;
  vBaseDecimals?: number;
  uniswapFeeTierDefault?: number;
  rBaseAddress?: string;
}

interface InitializePoolArgs {
  rageTradeFactory: RageTradeFactory;

  // initialize pool struct
  liquidityFeePips?: BigNumberish;
  protocolFeePips?: BigNumberish;

  // DeployVTokenParamsStructOutput
  vTokenName?: string;
  vTokenSymbol?: string;
  // rTokenAddress?: string;
  // oracleAddress?: string;
  vTokenDecimals?: number;

  // rage trade pool settings
  initialMarginRatio?: number;
  maintainanceMarginRatio?: number;
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
  vBaseDecimals,
  uniswapFeeTierDefault,
  rBaseAddress,
}: SetupClearingHouseArgs) {
  vBaseDecimals = vBaseDecimals ?? 6;

  uniswapFeeTierDefault = uniswapFeeTierDefault ?? +UNISWAP_V3_DEFAULT_FEE_TIER;
  signer = signer ?? (await hre.ethers.getSigners())[0];

  // real base
  let rBase: ERC20;
  if (rBaseAddress) {
    rBase = await hre.ethers.getContractAt('ERC20', rBaseAddress);
  } else {
    const _rBase = await (await hre.ethers.getContractFactory('RealTokenMock')).deploy();
    const d = await _rBase.decimals();
    await _rBase.mint(signer.address, parseUnits('100000', d));
    rBase = _rBase;
  }
  hre.tracer.nameTags[rBase.address] = 'rBase';

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

  const insuranceFundAddressComputed = await getCreateAddressFor(signer, 1);

  // rage trade factory
  const rageTradeFactory = await (
    await hre.ethers.getContractFactory('RageTradeFactory')
  ).deploy(
    clearingHouseLogic.address,
    vPoolWrapperLogic.address,
    rBase.address,
    insuranceFundAddressComputed,
    UNISWAP_V3_FACTORY_ADDRESS,
    UNISWAP_V3_DEFAULT_FEE_TIER,
    UNISWAP_V3_POOL_BYTE_CODE_HASH,
  );

  // virtual base
  const vBase = await hre.ethers.getContractAt('VBase', await rageTradeFactory.vBase());
  hre.tracer.nameTags[vBase.address] = 'vBase';

  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());
  hre.tracer.nameTags[clearingHouse.address] = 'clearingHouse';

  const proxyAdmin = await hre.ethers.getContractAt('ProxyAdmin', await rageTradeFactory.proxyAdmin());
  hre.tracer.nameTags[proxyAdmin.address] = 'proxyAdmin';

  const insuranceFund = await (
    await hre.ethers.getContractFactory('InsuranceFund')
  ).deploy(rBase.address, clearingHouse.address);

  return {
    signer,
    rBase,
    vBase,
    clearingHouse,
    proxyAdmin,
    clearingHouseLogic,
    accountLib,
    rageTradeFactory,
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
  initialMarginRatio,
  maintainanceMarginRatio,
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

  initialMarginRatio = initialMarginRatio ?? 20000;
  maintainanceMarginRatio = maintainanceMarginRatio ?? 10000;
  twapDuration = twapDuration ?? 60;
  whitelisted = whitelisted ?? false;

  vPriceInitial = vPriceInitial ?? 1;
  rPriceInitial = rPriceInitial ?? 1;

  const vBaseDecimalsDefault = 6;
  vTokenDecimals = vTokenDecimals ?? 18;

  const realToken = await smock.fake<RealTokenMock>('RealTokenMock');
  realToken.decimals.returns(vTokenDecimals);

  // oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
  await oracle.setSqrtPrice(await priceToSqrtPriceX96(rPriceInitial, vBaseDecimalsDefault, vTokenDecimals));

  await rageTradeFactory.initializePool({
    deployVTokenParams: {
      vTokenName: 'vWETH',
      vTokenSymbol: 'vWETH',
      rTokenAddress: realToken.address,
      oracleAddress: oracle.address,
    },
    rageTradePoolInitialSettings: {
      initialMarginRatio,
      maintainanceMarginRatio,
      twapDuration,
      whitelisted: false,
      oracle: oracle.address,
    },
    liquidityFeePips: 500,
    protocolFeePips: 500,
  });

  const eventFilter = rageTradeFactory.filters.PoolInitlized();
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
  const vBase = await hre.ethers.getContractAt('VBase', await rageTradeFactory.vBase());
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());
  const proxyAdmin = await hre.ethers.getContractAt('ProxyAdmin', await rageTradeFactory.proxyAdmin());
  return { vBase, clearingHouse, proxyAdmin };
}
