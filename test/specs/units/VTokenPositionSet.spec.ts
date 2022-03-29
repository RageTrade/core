import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import {
  VTokenPositionSetTest,
  RageTradeFactory,
  VQuote,
  VPoolWrapper,
  ERC20,
  UniswapV3Pool,
  ClearingHouse,
} from '../../../typechain-types';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  SETTLEMENT_TOKEN,
} from '../../utils/realConstants';
import { config } from 'dotenv';
import { activateMainnetFork, deactivateMainnetFork } from '../../utils/mainnet-fork';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getCreateAddressFor } from '../../utils/create-addresses';
import { ADDRESS_ZERO } from '@uniswap/v3-sdk';
import { impersonateAccount } from '../../utils/impersonate-account';
import { truncate } from '../../utils/vToken';

const realToken0 = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
const realToken1 = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';

describe('VTokenPositionSet Library', () => {
  // const vTokenAddress: string = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  // const vTokenAddress1: string = utils.hexZeroPad(BigNumber.from(2).toHexString(), 20);
  let VTokenPositionSet: VTokenPositionSetTest;
  let vTokenAddress: string;
  let vTokenAddress1: string;
  let rageTradeFactory: RageTradeFactory;
  let vQuote: VQuote;
  let VPoolWrapper: VPoolWrapper;
  let clearingHouse: ClearingHouse;
  // let constants: ConstantsStruct;
  let signers: SignerWithAddress[];
  let chSigner: SignerWithAddress;
  before(async () => {
    await activateMainnetFork();

    const settlementToken = await smock.fake<ERC20>('ERC20');
    settlementToken.decimals.returns(10);
    // VQuote = await (await hre.ethers.getContractFactory('VQuote')).deploy(settlementToken.address);
    const oracleAddress = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;

    signers = await hre.ethers.getSigners();
    const futureVPoolFactoryAddress = await getCreateAddressFor(signers[0], 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(signers[0], 4);

    // const VPoolWrapperDeployer = await (
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

    rageTradeFactory = await (
      await hre.ethers.getContractFactory('RageTradeFactory')
    ).deploy(clearingHouseLogic.address, vPoolWrapperLogic.address, insuranceFundLogic.address, SETTLEMENT_TOKEN);

    clearingHouse = await hre.ethers.getContractAt('ClearingHouse', await rageTradeFactory.clearingHouse());
    chSigner = await impersonateAccount(clearingHouse.address);
    vQuote = await hre.ethers.getContractAt('VQuote', await rageTradeFactory.vQuote());

    const insuranceFund = await hre.ethers.getContractAt('InsuranceFund', await clearingHouse.insuranceFund());

    // await VQuote.transferOwnership(VPoolFactory.address);

    await rageTradeFactory.initializePool({
      deployVTokenParams: {
        vTokenName: 'vWETH',
        vTokenSymbol: 'vWETH',
        cTokenDecimals: 18,
      },
      poolInitialSettings: {
        initialMarginRatioBps: 2,
        maintainanceMarginRatioBps: 3,
        maxVirtualPriceDeviationRatioBps: 10000,
        twapDuration: 2,
        isAllowedForTrade: false,
        isCrossMargined: false,
        oracle: oracleAddress,
      },
      liquidityFeePips: 500,
      protocolFeePips: 500,
      slotsToInitialize: 100,
    });

    const eventFilter = rageTradeFactory.filters.PoolInitialized();
    const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');
    vTokenAddress = events[0].args[1];
    // console.log('vTokenAddres', vTokenAddress);
    // console.log('VPoolFactoryAddress', VPoolFactory.address);
    // console.log('Vwrapper', events[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);
    const vPoolAddress = ADDRESS_ZERO;
    const vPoolFake = await smock.fake<UniswapV3Pool>(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      {
        address: vPoolAddress,
      },
    );
    await VPoolWrapper.connect(chSigner).mint(-10, 10, 10000000000000, { gasPrice: 0 });

    await rageTradeFactory.initializePool({
      deployVTokenParams: {
        vTokenName: 'vWETH',
        vTokenSymbol: 'vWETH',
        cTokenDecimals: 18,
      },
      poolInitialSettings: {
        initialMarginRatioBps: 2,
        maintainanceMarginRatioBps: 3,
        maxVirtualPriceDeviationRatioBps: 10000,
        twapDuration: 2,
        isAllowedForTrade: true,
        isCrossMargined: false,
        oracle: oracleAddress,
      },
      liquidityFeePips: 500,
      protocolFeePips: 500,
      slotsToInitialize: 100,
    });

    const eventFilter1 = rageTradeFactory.filters.PoolInitialized();
    const events1 = await rageTradeFactory.queryFilter(eventFilter1, 'latest');
    vTokenAddress1 = events1[0].args[1];
    // console.log('vTokenAddres1', vTokenAddress);
    // console.log('VPoolFactoryAddress1', VPoolFactory.address);
    // console.log('Vwrapper1', events1[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events1[0].args[2]);
    await VPoolWrapper.connect(chSigner).mint(-10, 10, 10000000000000, { gasPrice: 0 });

    const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
    VTokenPositionSet = await factory.deploy();

    // constants = await VPoolFactory.constants();
    await setConstants(VTokenPositionSet);
  });

  after(deactivateMainnetFork);

  describe('Functions', () => {
    it('Activate', async () => {
      await VTokenPositionSet.init(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(0);
      expect(resultVQuote.balance).to.eq(0);
    });

    it('Update', async () => {
      await VTokenPositionSet.update(
        {
          vQuoteIncrease: 10,
          vTokenIncrease: 20,
          traderPositionIncrease: 30,
        },
        vTokenAddress,
      );
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(20);
      expect(resultVToken.netTraderPosition).to.eq(30);
      expect(resultVQuote.balance).to.eq(10);
    });

    it('Realized Funding Payment', async () => {
      await VTokenPositionSet.realizeFundingPaymentToAccount(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.sumALastX128).to.eq((20n * 1n) << 128n);
      expect(resultVQuote.balance).to.eq(-590);
    });
  });

  describe('Token Swaps (Token Amount)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = await factory.deploy();

      await setConstants(VTokenPositionSet);
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress, 4);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVQuote.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress1, 2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVQuote.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVQuote.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVQuote.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Token Swaps (Token Notional)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = await factory.deploy();

      await setConstants(VTokenPositionSet);
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress, 16000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVQuote.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress1, 8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVQuote.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVQuote.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVQuote.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Liquidity Change', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = await factory.deploy();
      await VTokenPositionSet.init(vTokenAddress);

      await setConstants(VTokenPositionSet);
    });

    it('Add Liquidity', async () => {
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, 100);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();

      expect(resultVToken.balance).to.eq(-100);
      // expect(resultVToken.netTraderPosition).to.eq(-100);
      expect(resultVQuote.balance).to.eq(-400000);
    });

    it('Remove Liquidity', async () => {
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, -50);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();

      expect(resultVToken.balance).to.eq(-50);
      // expect(resultVToken.netTraderPosition).to.eq(-50);
      expect(resultVQuote.balance).to.eq(-200000);
    });
  });

  describe('Liquididate Liquidity Positions (For a token)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);

      await setConstants(VTokenPositionSet);

      await VTokenPositionSet.liquidityChange(vTokenAddress, -100, 100, 100);
      await VTokenPositionSet.liquidityChange(vTokenAddress, -50, 50, 100);
    });

    it('Liquidate Liquidity Position', async () => {
      let resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      let resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(-200);
      expect(resultVQuote.balance).to.eq(-800000);

      await VTokenPositionSet.liquidateLiquidityPositions(vTokenAddress);

      resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      resultVQuote = await VTokenPositionSet.functions.getVQuoteBalance();
      expect(resultVToken.balance).to.eq(0);
      expect(resultVQuote.balance).to.eq(0);
    });
  });

  async function setConstants(vTokenPositionSet: VTokenPositionSetTest) {
    const vTokenPoolObj = await clearingHouse.getPoolInfo(truncate(vTokenAddress));
    await vTokenPositionSet.registerPool(vTokenPoolObj);

    const vTokenPoolObj1 = await clearingHouse.getPoolInfo(truncate(vTokenAddress1));
    await vTokenPositionSet.registerPool(vTokenPoolObj1);

    await vTokenPositionSet.setVQuoteAddress(vQuote.address);
  }
});
