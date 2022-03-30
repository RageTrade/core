import { expect } from 'chai';
import hre from 'hardhat';
import { BigNumber, BigNumberish, utils } from 'ethers';
import { VTokenPositionSetTest2, VPoolWrapper, UniswapV3Pool, VQuote, ClearingHouse } from '../../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetup } from '../helpers/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from '../helpers/mainnet-fork';
import { truncate } from '../helpers/vToken';
import { tickToSqrtPriceX96 } from '../helpers/price-tick';

describe('Market Value and Required Margin', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  let vQuote: VQuote;
  let clearingHouse: ClearingHouse;
  // let constants: ConstantsStruct;
  let vTokenAddress: string;

  const matchNumbers = async (mktVal: number, initialMargin: number, maintMargin: number) => {
    expect(await VTokenPositionSet.getAllTokenPositionValue()).to.be.eq(BigNumber.from(mktVal));
    expect(await VTokenPositionSet.getRequiredMargin(true)).to.be.eq(BigNumber.from(initialMargin));
    expect(await VTokenPositionSet.getRequiredMargin(false)).to.be.eq(BigNumber.from(maintMargin));
  };

  const liqChange = async (tickLower: number, tickUpper: number, liq: number) => {
    await VTokenPositionSet.liquidityChange(vTokenAddress, {
      tickLower: tickLower,
      tickUpper: tickUpper,
      liquidityDelta: BigNumber.from(liq).mul(BigNumber.from(10).pow(12)),
      closeTokenPosition: false,
      limitOrderType: 0,
      sqrtPriceCurrent: 0,
      slippageToleranceBps: 0,
    });
  };

  const liqChange1 = async (tickLower: number, tickUpper: number, liq: BigNumberish) => {
    await VTokenPositionSet.liquidityChange(vTokenAddress, {
      tickLower: tickLower,
      tickUpper: tickUpper,
      liquidityDelta: liq,
      closeTokenPosition: false,
      limitOrderType: 0,
      sqrtPriceCurrent: 0,
      slippageToleranceBps: 0,
    });
  };

  const swap = async (amount: BigNumberish, sqrtPriceLimit: number, isNotional: boolean, isPartialAllowed: boolean) => {
    const swapParams = {
      amount: amount,
      sqrtPriceLimit: sqrtPriceLimit,
      isNotional: isNotional,
      isPartialAllowed: isPartialAllowed,
    };
    await VTokenPositionSet.swap(vTokenAddress, swapParams);
  };

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;
    ({
      vTokenAddress: vTokenAddress,
      vPoolAddress: vPoolAddress,
      vPoolWrapperAddress: vPoolWrapperAddress,
      clearingHouse,
      vQuote,
    } = await testSetup({
      initialMarginRatioBps: 2000,
      maintainanceMarginRatioBps: 1000,
      twapDuration: 60,
      whitelisted: true,
    }));
    vPoolFake = await smock.fake<UniswapV3Pool>(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      {
        address: vPoolAddress,
      },
    );
    vPoolFake.observe.returns([[0, -194430 * 60], []]);
    const sqrtPriceX96 = tickToSqrtPriceX96(-194430);
    vPoolFake.slot0.returns([sqrtPriceX96, -194430, 0, 0, 0, 0, false]);

    vPoolWrapperFake = await smock.fake<VPoolWrapper>('VPoolWrapper', {
      address: vPoolWrapperAddress,
    });
    // vPoolWrapperFake.timeHorizon.returns(60);
    // vPoolWrapperFake.maintainanceMarginRatio.returns(10000);
    // vPoolWrapperFake.initialMarginRatio.returns(20000);
    vPoolWrapperFake.vPool.returns(vPoolFake.address);

    const myContractFactory = await smock.mock('VTokenPositionSetTest2');
    VTokenPositionSet = (await myContractFactory.deploy()) as unknown as MockContract<VTokenPositionSetTest2>;
    await VTokenPositionSet.init(vTokenAddress);

    const vTokenPoolObj = await clearingHouse.getPoolInfo(truncate(vTokenAddress));
    await VTokenPositionSet.registerPool(vTokenPoolObj);

    await VTokenPositionSet.setVQuoteAddress(vQuote.address);
  });
  after(deactivateMainnetFork);
  describe('Base Case', () => {
    // Add range In Between
    // ##### State #####
    // a. CurrentTWAPTick: 194430
    // b. tickLow: 193370
    // c. tickHigh: 195660
    // d. liquidity: 35000 * 10**12
    // vUSDC Minted 125271.786680
    // vToken Minted 30.105615887850845791
    // netToken Position 0
    // ##### Assertions #####
    // MktVal 0
    // ReqMargin (MaintenanceMargin) 13321.7428693545
    // ReqMargin (InitialMargin) 26643.485738709
    it('Scenario 1 - Add Range', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('30105615887850845791'),
        125271786680,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('30105615887850845791'),
        125271786680,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange(-195660, -193370, 35000);
      await matchNumbers(0, 25054357336, 12527178668);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 193170
    // ##### Assertions #####
    // MktVal -8656.594064
    // ReqMargin (MaintenanceMargin) 15110.520196929
    // ReqMargin (InitialMargin) 30221.0403938581
    it('Scenario 2 - Price Moves', async () => {
      vPoolFake.observe.returns([[0, -193170 * 60], []]);
      const tick = -193170;
      const sqrtPriceX96 = tickToSqrtPriceX96(tick);
      vPoolFake.slot0.returns([sqrtPriceX96, tick, 0, 0, 0, 0, false]);
      await matchNumbers(-8656594064, 26417987111, 13208993555);
    });

    // Add range outside
    // a. CurrentTwapTick: 193170
    // b. tickLow: 193370
    // c. tickHigh: 195660
    // d. liquidity: 35000 * 10**12
    // ##### Assertions #####
    // MktVal -8656.594064
    //  ReqMargin (MaintenanceMargin) 42518.0764004743
    // ReqMargin (InitialMargin) 85036.1528009486
    it('Scenario 3 - Add Range Outside', async () => {
      vPoolWrapperFake.mint.returns([
        0,
        239585552683,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        239585552683,
        0,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange(-195660, -193370, 35000);
      await matchNumbers(-8656594064, 71240149059, 35620074529);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 194690
    // ##### Assertions #####
    // MktVal -9383544194
    // ReqMargin (MaintenanceMargin) 36522806901
    // ReqMargin (InitialMargin) 73045.613802876
    it('Scenario 4 - Price Moves', async () => {
      const tick = -194690;
      vPoolFake.observe.returns([[0, tick * 60], []]);
      const sqrtPriceX96 = tickToSqrtPriceX96(tick);
      vPoolFake.slot0.returns([sqrtPriceX96, tick, 0, 0, 0, 0, false]);

      await matchNumbers(-9383544194, 68587488054, 34293744027);
    });

    // Add range outside
    // a. CurrentTwapTick: 194690
    // b. tickLow: 193370
    // c. tickHigh: 195660
    // d. liquidity: 25000 * 10**12
    // ##### Assertions #####
    // MktVal -9383544194
    // ReqMargin (MaintenanceMargin) 43881.5805109528
    // ReqMargin (InitialMargin) 87763.1610219056
    it('Scenario 5 - Add Range Outside', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('26954936243705637801'),
        70104066864,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        70104066864,
        BigNumber.from('26954936243705637801'),
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange(-195660, -193370, 25000);
      await matchNumbers(-9383544194, 85115572406, 42557786203);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 196480
    // ##### Assertions #####
    // MktVal -68061639307
    // ReqMargin (MaintenanceMargin) 36689.976692
    // ReqMargin (InitialMargin) 73379.953383
    it('Scenario 6 - Price Moves', async () => {
      const tick = -196480;
      vPoolFake.observe.returns([[0, tick * 60], []]);
      const sqrtPriceX96 = tickToSqrtPriceX96(tick);
      vPoolFake.slot0.returns([sqrtPriceX96, tick, 0, 0, 0, 0, false]);

      await matchNumbers(-68061639307, 75336901712, 37668450856);
    });
  });
  describe('Additional Cases', () => {
    beforeEach(async () => {
      const myContractFactory = await smock.mock('VTokenPositionSetTest2');
      VTokenPositionSet = (await myContractFactory.deploy()) as unknown as MockContract<VTokenPositionSetTest2>;
      await VTokenPositionSet.init(vTokenAddress);

      const vTokenPoolObj = await clearingHouse.getPoolInfo(truncate(vTokenAddress));
      await VTokenPositionSet.registerPool(vTokenPoolObj);

      await VTokenPositionSet.setVQuoteAddress(vQuote.address);

      const tick = -198080;
      vPoolFake.observe.returns([[0, tick * 60], []]);
      const sqrtPriceX96 = tickToSqrtPriceX96(tick);
      vPoolFake.slot0.returns([sqrtPriceX96, tick, 0, 0, 0, 0, false]);
    });
    it('Scenario 1 - Full Range', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('200000000000000000000'),
        499982719827,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('200000000000000000000'),
        499982719827,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-290188, -105972, 10100835597258300n);
      await matchNumbers(0, 99996543965, 49998271982);
    });

    it('Scenario 2 - Concentrated Range (Same Liquidity as full range)', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('101011935963275000000'),
        252508487108,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('101011935963275000000'),
        252508487108,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-211943, -184216, 10100835597258600n);
      await matchNumbers(0, 50504222477, 25252111238);
    });

    it('Scenario 3 - Concentrated Range (Same notional value of assets as full range)', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('200000000000000000000'),
        499957722224,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('200000000000000000000'),
        499957722224,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-211943, -184216, 19999291174720100n);
      await matchNumbers(0, 99996543964, 49998271982);
    });

    it('Scenario 4 - Short Trade Position + Long Range)', async () => {
      vPoolWrapperFake.swap.returns([
        {
          amountSpecified: 100000000000000000000n,
          vTokenIn: 100000000000000000000n,
          vQuoteIn: -249991359911n,
          liquidityFees: 0,
          protocolFees: 0,
          sqrtPriceX96Start: 0,
          sqrtPriceX96End: 0,
        },
      ]);
      await swap(-100000000000000000000n, 0, false, false);

      await matchNumbers(0, 49998271982, 24999135991);

      vPoolWrapperFake.mint.returns([
        BigNumber.from('0'),
        499999999998,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('0'),
        499999999998,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-290188, -198080, 10101184697695600n);
      await matchNumbers(0, 50001728017, 25000864008);
    });

    it('Scenario 5 - Long Trade Position + Short Range)', async () => {
      vPoolWrapperFake.swap.returns([
        {
          amountSpecified: -100000000000000000000n,
          vTokenIn: -100000000000000000000n,
          vQuoteIn: 249991359914n,
          liquidityFees: 0,
          protocolFees: 0,
          sqrtPriceX96Start: 0,
          sqrtPriceX96End: 0,
        },
      ]);
      await swap(100000000000000000000n, 0, false, false);

      await matchNumbers(-3, 49998271982, 24999135991);

      vPoolWrapperFake.mint.returns([
        BigNumber.from('200000000000000000000'),
        0,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('200000000000000000000'),
        0,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-198080, -105972, 10100835597258300n);
      await matchNumbers(0, 49998271982, 24999135991);
    });

    it('Scenario 6 - Long Range + Short Range)', async () => {
      vPoolWrapperFake.mint.returns([
        BigNumber.from('0'),
        500000000000,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('0'),
        500000000000,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-290188, -198080, 10101184697695600n);
      await matchNumbers(-2, 99999999999, 49999999999);

      vPoolWrapperFake.mint.returns([
        BigNumber.from('200000000000000000000'),
        0,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      vPoolWrapperFake.burn.returns([
        BigNumber.from('200000000000000000000'),
        0,
        {
          sumAX128: 0,
          sumBInsideX128: 0,
          sumFpInsideX128: 0,
          sumFeeInsideX128: 0,
        },
      ]);
      await liqChange1(-198080, -105972, 10100835597258300n);
      await matchNumbers(0, 99999999999, 49999999999);
    });
  });
});
