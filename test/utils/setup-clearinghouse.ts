import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers } from 'ethers';
import { parseUnits } from 'ethers/lib/utils';
import hre from 'hardhat';
import { ClearingHouse, ERC20, VBase, VPoolFactory } from '../../typechain-types';
import { getCreateAddressFor } from './create-addresses';
import { priceToSqrtPriceX96 } from './price-tick';
import { randomAddress } from './random';
import { DEFAULT_FEE_TIER, UNISWAP_V3_POOL_BYTE_CODE_HASH, UNISWAP_FACTORY_ADDRESS } from './realConstants';

interface SetupClearingHouseArgs {
  signer?: SignerWithAddress;
  vBaseDecimals?: number;
  uniswapFeeTierDefault?: number;
  rBaseAddress?: string;
}

interface InitializePoolArgs {
  vPoolFactory: VPoolFactory;
  initialMarginRatio?: number;
  maintainanceMarginRatio?: number;
  twapDuration?: number;
  vPriceInitial: number;
  rPriceInitial: number;
  vBaseDecimals?: number;
  vTokenDecimals?: number;
  uniswapFee?: number;
  liquidityFee?: number;
  protocolFee?: number;
  signer?: SignerWithAddress;
  vBase?: VBase;
}

// sets up clearing house with upgradable logic
export async function setupClearingHouse({
  signer,
  vBaseDecimals,
  uniswapFeeTierDefault,
  rBaseAddress,
}: SetupClearingHouseArgs) {
  vBaseDecimals = vBaseDecimals ?? 6;

  uniswapFeeTierDefault = uniswapFeeTierDefault ?? +DEFAULT_FEE_TIER;
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

  // virtual base
  const vBase = await (await hre.ethers.getContractFactory('VBase')).deploy(rBase.address);
  hre.tracer.nameTags[vBase.address] = 'vBase';

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
  ).deploy(futureVPoolFactoryAddress, rBase.address, futureInsurnaceFundAddress);

  // proxy deployment
  const proxyAdmin = await (await hre.ethers.getContractFactory('ProxyAdmin')).deploy();
  const clearingHouseProxy = await (
    await hre.ethers.getContractFactory('TransparentUpgradeableProxy')
  ).deploy(clearingHouseLogic.address, proxyAdmin.address, '0x');
  const clearingHouse = await hre.ethers.getContractAt('ClearingHouse', clearingHouseProxy.address);

  // wrapper deployer
  const vPoolWrapperDeployer = await (
    await hre.ethers.getContractFactory('VPoolWrapperDeployer')
  ).deploy(futureVPoolFactoryAddress);

  // vPool factory
  const vPoolFactory = await (
    await hre.ethers.getContractFactory('VPoolFactory')
  ).deploy(
    vBase.address,
    clearingHouse.address,
    vPoolWrapperDeployer.address,
    UNISWAP_FACTORY_ADDRESS,
    uniswapFeeTierDefault,
    UNISWAP_V3_POOL_BYTE_CODE_HASH,
  );

  const insuranceFund = await (
    await hre.ethers.getContractFactory('InsuranceFund')
  ).deploy(rBase.address, clearingHouse.address);

  return {
    signer,
    rBase,
    vBase,
    clearingHouse,
    clearingHouseLogic,
    accountLib,
    clearingHouseProxy,
    proxyAdmin,
    vPoolWrapperDeployer,
    vPoolFactory,
    insuranceFund,
    upgradeClearingHouse,
  };

  async function upgradeClearingHouse(newClearingHouseLogicAddress: string) {
    // clearingHouse.upgradeTo can only be called by proxyAdmin contract
    await proxyAdmin.upgrade(clearingHouse.address, newClearingHouseLogicAddress);
  }
}

// TODO: finish this deployment setup
export async function initializePool({
  initialMarginRatio,
  maintainanceMarginRatio,
  twapDuration,
  vPriceInitial,
  rPriceInitial,
  vBaseDecimals,
  vTokenDecimals,
  liquidityFee,
  protocolFee,
  signer,
  vBase,
  vPoolFactory,
}: InitializePoolArgs) {
  initialMarginRatio = initialMarginRatio ?? 20000;
  maintainanceMarginRatio = maintainanceMarginRatio ?? 10000;
  twapDuration = twapDuration ?? 60;

  rPriceInitial = rPriceInitial ?? 1;
  vBaseDecimals = vBaseDecimals ?? 6;
  vTokenDecimals = vTokenDecimals ?? 18;

  // oracle
  const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
  await oracle.setSqrtPrice(await priceToSqrtPriceX96(rPriceInitial, vBaseDecimals, vTokenDecimals));

  await vPoolFactory.initializePool(
    {
      setupVTokenParams: {
        vTokenName: 'vTest',
        vTokenSymbol: 'vTest',
        realTokenAddress: ethers.constants.AddressZero,
        oracleAddress: oracle.address,
      },
      extendedLpFee: 500,
      protocolFee: 500,
      initialMarginRatio,
      maintainanceMarginRatio,
      twapDuration,
      whitelisted: false,
    },
    0,
  );
}
