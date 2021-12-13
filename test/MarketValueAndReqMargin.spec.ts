import { expect } from 'chai';
import hre from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest2, VPoolWrapper, UniswapV3Pool, OracleTest } from '../typechain-types';
import { MockContract, FakeContract } from '@defi-wonderland/smock';
import { smock } from '@defi-wonderland/smock';
import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import { testSetup } from './utils/setup-general';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';

describe('VTokenPositionSet Library', () => {
  let VTokenPositionSet: MockContract<VTokenPositionSetTest2>;
  let vPoolFake: FakeContract<UniswapV3Pool>;
  let vPoolWrapperFake: FakeContract<VPoolWrapper>;
  let constants: ConstantsStruct;
  let vTokenAddress: string;

  const matchNumbers = async (mktVal: number, initialMargin: number, maintMargin: number) => {
    expect(await VTokenPositionSet.getAllTokenPositionValue(constants)).to.be.eq(BigNumber.from(mktVal));
    expect(await VTokenPositionSet.getRequiredMargin(true, constants)).to.be.eq(BigNumber.from(initialMargin));
    expect(await VTokenPositionSet.getRequiredMargin(false, constants)).to.be.eq(BigNumber.from(maintMargin));
  };

  const liqChange = async (tickLower: number, tickUpper: number, liq: number) => {
    await VTokenPositionSet.liquidityChange(
      vTokenAddress,
      {
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: BigNumber.from(liq).mul(BigNumber.from(10).pow(12)),
        closeTokenPosition: false,
        limitOrderType: 0,
        sqrtPriceCurrent: 0,
        slippageTolerance: 0,
      },
      constants,
    );
  };

  before(async () => {
    await activateMainnetFork();
    let vPoolAddress;
    let vPoolWrapperAddress;
    ({
      vTokenAddress: vTokenAddress,
      vPoolAddress: vPoolAddress,
      vPoolWrapperAddress: vPoolWrapperAddress,
      constants: constants,
    } = await testSetup({
      initialMarginRatio: 20000,
      maintainanceMarginRatio: 10000,
      twapDuration: 60,
      isVTokenToken0: false,
      whitelisted: true,
    }));
    vPoolFake = await smock.fake<UniswapV3Pool>('IUniswapV3Pool', {
      address: vPoolAddress,
    });
    vPoolFake.observe.returns([[0, 194430 * 60], []]);

    vPoolWrapperFake = await smock.fake<VPoolWrapper>('VPoolWrapper', {
      address: vPoolWrapperAddress,
    });
    vPoolWrapperFake.timeHorizon.returns(60);
    vPoolWrapperFake.maintainanceMarginRatio.returns(10000);
    vPoolWrapperFake.initialMarginRatio.returns(20000);

    const myContractFactory = await smock.mock('VTokenPositionSetTest2');
    VTokenPositionSet = (await myContractFactory.deploy()) as unknown as MockContract<VTokenPositionSetTest2>;
    await VTokenPositionSet.init(vTokenAddress);
  });
  after(deactivateMainnetFork);
  describe('MarketValue and RequiredMargin', () => {
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
      vPoolWrapperFake.liquidityChange.returns([125271786680, BigNumber.from('30105615887850845791')]);
      await liqChange(193370, 195660, 35000);
      await matchNumbers(0, 26643485738, 13321742869);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 193170
    // ##### Assertions #####
    // MktVal -8656.594064
    // ReqMargin (MaintenanceMargin) 15110.520196929
    // ReqMargin (InitialMargin) 30221.0403938581
    it('Scenario 2 - Price Moves', async () => {
      vPoolFake.observe.returns([[0, 193170 * 60], []]);
      await matchNumbers(-8656594064, 30221040393, 15110520196);
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
      vPoolWrapperFake.liquidityChange.returns([239585552683, 0]);
      await liqChange(193370, 195660, 35000);
      await matchNumbers(-8656594064, 85036152800, 42518076400);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 194690
    // ##### Assertions #####
    // MktVal -9383544194
    // ReqMargin (MaintenanceMargin) 36522806901
    // ReqMargin (InitialMargin) 73045.613802876
    it('Scenario 4 - Price Moves', async () => {
      vPoolFake.observe.returns([[0, 194690 * 60], []]);
      await matchNumbers(-9383544194, 73045613802, 36522806901);
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
      vPoolWrapperFake.liquidityChange.returns([70104066864, BigNumber.from('26954936243705637801')]);
      await liqChange(193370, 195660, 25000);
      await matchNumbers(-9383544194, 87763161021, 43881580510);
    });

    // Price Changes
    // ##### State #####
    // a. CurrentTwapTick = 196480
    // ##### Assertions #####
    // MktVal -68061639307
    // ReqMargin (MaintenanceMargin) 36689.976692
    // ReqMargin (InitialMargin) 73379.953383
    it('Scenario 6 - Price Moves', async () => {
      vPoolFake.observe.returns([[0, 196480 * 60], []]);
      await matchNumbers(-68061639307, 73379953383, 36689976691);
    });
  });
});
