import { expect } from 'chai';
import { BigNumber } from 'ethers';
import hre from 'hardhat';

import { GlobalUtilLibTest } from '../typechain';

const fundingRateNormalizer = BigNumber.from(10000 * 100 * 3600);

function getExtrapolatedSumA(
  globalSumA: BigNumber,
  globalFundingRate: BigNumber,
  lastTS: BigNumber,
  globalLastTradeTS: BigNumber,
  price: BigNumber,
) {
  return globalSumA.add(globalFundingRate.mul(price).mul(lastTS.sub(globalLastTradeTS)).div(fundingRateNormalizer));
}
function getExtrapolatedSumFP(
  sumACkpt: BigNumber,
  sumBCkpt: BigNumber,
  sumFPCkpt: BigNumber,
  globalSumA: BigNumber,
  globalFundingRate: BigNumber,
  lastTS: BigNumber,
  globalLastTradeTS: BigNumber,
  price: BigNumber,
) {
  return sumFPCkpt.add(
    sumBCkpt.mul(getExtrapolatedSumA(globalSumA, globalFundingRate, lastTS, globalLastTradeTS, price).sub(sumACkpt)),
  );
}
describe('Tick Util Library', () => {
  let test: GlobalUtilLibTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('GlobalUtilLibTest');
    test = await factory.deploy();
  });

  describe('#Extrapolation', () => {
    it('SumA Extrapolation', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(1);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');
      const price = BigNumber.from('4000000000000000000000');

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      await test.setBlockTimestamp(endTS);
      const extrapolatedSumA = await test.getExtrapolatedSumA();

      expect(extrapolatedSumA).to.eq(
        getExtrapolatedSumA(globalSumA, globalFundingRate, endTS, globalLastTradeTS, price),
      );
    });

    it('SumFP Extrapolation', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const tickLowerSumA = BigNumber.from('20000000000000000000');
      const tickLowerSumBOutside = BigNumber.from('30000000000000000000');
      const tickLowerSumFPOutside = BigNumber.from('500000000000000000000');
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickLowerIndex = BigNumber.from(500);

      const tickHigherSumA = BigNumber.from('20000000000000000000');
      const tickHigherSumBOutside = BigNumber.from('30000000000000000000');
      const tickHigherSumFPOutside = BigNumber.from('500000000000000000000');
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickHigherIndex = BigNumber.from(1500);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');

      const price = BigNumber.from('4000000000000000000000');

      const sumACkpt = BigNumber.from('1000000000000000000');
      const sumBCkpt = BigNumber.from('5000000000000000000');
      const sumFPCkpt = BigNumber.from('100000000000000000000');

      await test.initializeTickState(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        tickLowerFeeGrowthOutsideShortsX128,
        tickLowerIndex,
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        tickHigherFeeGrowthOutsideShortsX128,
        tickHigherIndex,
      );

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      await test.setBlockTimestamp(endTS);
      const extrapolatedSumFP = await test.getExtrapolatedSumFP(sumACkpt, sumBCkpt, sumFPCkpt);

      expect(extrapolatedSumFP).to.eq(
        getExtrapolatedSumFP(
          sumACkpt,
          sumBCkpt,
          sumFPCkpt,
          globalSumA,
          globalFundingRate,
          endTS,
          globalLastTradeTS,
          price,
        ),
      );
    });
  });

  describe('#Trade Update', () => {
    it('Check 1', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');

      const tradeAmount = BigNumber.from('1000000000000000000');
      const fees = BigNumber.from('1000000000000000000');
      const liquidity = BigNumber.from('2000000000000000000000');

      const price = BigNumber.from('4000000000000000000000');

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      await test.setBlockTimestamp(endTS);
      await test.simulateUpdateOnTrade(tradeAmount, fees, liquidity);

      const global = await test.global();

      const a = price.mul(endTS.sub(globalLastTradeTS));

      expect(global.sumA).to.eq(globalSumA.add(a));
      expect(global.sumB).to.eq(globalSumB.add(tradeAmount.mul('1000000000000000000').div(liquidity)));
      expect(global.sumFP).to.eq(globalSumFP.add(globalFundingRate.mul(a).mul(globalSumB).div(fundingRateNormalizer)));
      expect(global.feeGrowthGlobalShortsX128).to.eq(
        globalFeeGrowthGlobalShortsX128.add(fees.mul('1000000000000000000').div(liquidity)),
      );
    });
  });

  describe('#LP State Update', () => {
    it('Position 0', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const tickLowerSumA = BigNumber.from('20000000000000000000');
      const tickLowerSumBOutside = BigNumber.from('30000000000000000000');
      const tickLowerSumFPOutside = BigNumber.from('500000000000000000000');
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from('30000000000000000000');
      const tickLowerIndex = BigNumber.from(1100);

      const tickHigherSumA = BigNumber.from('30000000000000000000');
      const tickHigherSumBOutside = BigNumber.from('40000000000000000000');
      const tickHigherSumFPOutside = BigNumber.from('600000000000000000000');
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from('20000000000000000000');
      const tickHigherIndex = BigNumber.from(1500);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');

      const price = BigNumber.from('4000000000000000000000');

      await test.initializeTickState(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        tickLowerFeeGrowthOutsideShortsX128,
        tickLowerIndex,
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        tickHigherFeeGrowthOutsideShortsX128,
        tickHigherIndex,
      );

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      test.setBlockTimestamp(endTS);
      const lpState = await test.getUpdatedLPState();

      // console.log("PRICE POSITION", await test.getPricePosition(1000));

      const lpStateSumA = lpState[0];
      const lpStateSumB = lpState[1];
      const lpStateSumFP = lpState[2];
      const lpStateFees = lpState[3];

      const tickLowerExtrapolatedSumFP = getExtrapolatedSumFP(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );
      const tickHigherExtrapolatedSumFP = getExtrapolatedSumFP(
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );

      expect(lpStateSumA).to.eq(getExtrapolatedSumA(globalSumA, globalFundingRate, endTS, globalLastTradeTS, price));
      expect(lpStateSumB).to.eq(tickLowerSumBOutside.sub(tickHigherSumBOutside));
      expect(lpStateSumFP).to.eq(tickLowerExtrapolatedSumFP.sub(tickHigherExtrapolatedSumFP));
      expect(lpStateFees).to.eq(tickLowerFeeGrowthOutsideShortsX128.sub(tickHigherFeeGrowthOutsideShortsX128));
    });
    it('Position 1', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const tickLowerSumA = BigNumber.from('20000000000000000000');
      const tickLowerSumBOutside = BigNumber.from('30000000000000000000');
      const tickLowerSumFPOutside = BigNumber.from('500000000000000000000');
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickLowerIndex = BigNumber.from(500);

      const tickHigherSumA = BigNumber.from('20000000000000000000');
      const tickHigherSumBOutside = BigNumber.from('30000000000000000000');
      const tickHigherSumFPOutside = BigNumber.from('500000000000000000000');
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickHigherIndex = BigNumber.from(1500);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');

      const price = BigNumber.from('4000000000000000000000');

      await test.initializeTickState(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        tickLowerFeeGrowthOutsideShortsX128,
        tickLowerIndex,
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        tickHigherFeeGrowthOutsideShortsX128,
        tickHigherIndex,
      );

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      test.setBlockTimestamp(endTS);
      const lpState = await test.getUpdatedLPState();

      // console.log("PRICE POSITION", await test.getPricePosition(1000));

      const lpStateSumA = lpState[0];
      const lpStateSumB = lpState[1];
      const lpStateSumFP = lpState[2];
      const lpStateFees = lpState[3];

      const tickLowerExtrapolatedSumFP = getExtrapolatedSumFP(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );
      const tickHigherExtrapolatedSumFP = getExtrapolatedSumFP(
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );

      expect(lpStateSumA).to.eq(getExtrapolatedSumA(globalSumA, globalFundingRate, endTS, globalLastTradeTS, price));
      expect(lpStateSumB).to.eq(globalSumB.sub(tickHigherSumBOutside).sub(tickLowerSumBOutside));
      expect(lpStateSumFP).to.eq(globalSumFP.sub(tickLowerExtrapolatedSumFP).sub(tickHigherExtrapolatedSumFP));
      expect(lpStateFees).to.eq(
        globalFeeGrowthGlobalShortsX128
          .sub(tickLowerFeeGrowthOutsideShortsX128)
          .sub(tickHigherFeeGrowthOutsideShortsX128),
      );
    });

    it('Position 2', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const tickLowerSumA = BigNumber.from('20000000000000000000');
      const tickLowerSumBOutside = BigNumber.from('30000000000000000000');
      const tickLowerSumFPOutside = BigNumber.from('500000000000000000000');
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from('20000000000000000000');
      const tickLowerIndex = BigNumber.from(500);

      const tickHigherSumA = BigNumber.from('30000000000000000000');
      const tickHigherSumBOutside = BigNumber.from('40000000000000000000');
      const tickHigherSumFPOutside = BigNumber.from('600000000000000000000');
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from('40000000000000000000');
      const tickHigherIndex = BigNumber.from(800);

      const globalSumA = BigNumber.from('30000000000000000000');
      const globalSumB = BigNumber.from('150000000000000000000');
      const globalSumFP = BigNumber.from('1000000000000000000000');
      const globalLastTradeTS = startTS;
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');

      const price = BigNumber.from('4000000000000000000000');

      await test.initializeTickState(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        tickLowerFeeGrowthOutsideShortsX128,
        tickLowerIndex,
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        tickHigherFeeGrowthOutsideShortsX128,
        tickHigherIndex,
      );

      await test.initializeGlobalState(
        globalSumA,
        globalSumB,
        globalSumFP,
        globalLastTradeTS,
        globalFundingRate,
        globalFeeGrowthGlobalShortsX128,
      );

      test.setBlockTimestamp(endTS);
      const lpState = await test.getUpdatedLPState();

      // console.log("PRICE POSITION", await test.getPricePosition(1000));

      const lpStateSumA = lpState[0];
      const lpStateSumB = lpState[1];
      const lpStateSumFP = lpState[2];
      const lpStateFees = lpState[3];

      const tickLowerExtrapolatedSumFP = getExtrapolatedSumFP(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );
      const tickHigherExtrapolatedSumFP = getExtrapolatedSumFP(
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        globalSumA,
        globalFundingRate,
        endTS,
        globalLastTradeTS,
        price,
      );

      expect(lpStateSumA).to.eq(getExtrapolatedSumA(globalSumA, globalFundingRate, endTS, globalLastTradeTS, price));
      expect(lpStateSumB).to.eq(tickHigherSumBOutside.sub(tickLowerSumBOutside));
      expect(lpStateSumFP).to.eq(tickHigherExtrapolatedSumFP.sub(tickLowerExtrapolatedSumFP));
      expect(lpStateFees).to.eq(tickHigherFeeGrowthOutsideShortsX128.sub(tickLowerFeeGrowthOutsideShortsX128));
    });
  });

  describe('#Price Position', () => {
    it('All Positions', async () => {
      const startTS = BigNumber.from(100);
      const endTS = BigNumber.from(150);

      const tickLowerSumA = BigNumber.from('20000000000000000000');
      const tickLowerSumBOutside = BigNumber.from('30000000000000000000');
      const tickLowerSumFPOutside = BigNumber.from('500000000000000000000');
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickLowerIndex = BigNumber.from(500);

      const tickHigherSumA = BigNumber.from('20000000000000000000');
      const tickHigherSumBOutside = BigNumber.from('30000000000000000000');
      const tickHigherSumFPOutside = BigNumber.from('500000000000000000000');
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
      const tickHigherIndex = BigNumber.from(1500);

      await test.initializeTickState(
        tickLowerSumA,
        tickLowerSumBOutside,
        tickLowerSumFPOutside,
        tickLowerFeeGrowthOutsideShortsX128,
        tickLowerIndex,
        tickHigherSumA,
        tickHigherSumBOutside,
        tickHigherSumFPOutside,
        tickHigherFeeGrowthOutsideShortsX128,
        tickHigherIndex,
      );

      expect(0).to.eq(await test.getPricePosition(400));
      expect(1).to.eq(await test.getPricePosition(1000));
      expect(2).to.eq(await test.getPricePosition(1600));
    });
  });

  describe('#Funding Rate', () => {
    it('Check 1', async () => {
      const virtualPrice = BigNumber.from('4000000000000000000000');
      const realPrice = BigNumber.from('4100000000000000000000');

      const fundingRate = await test.calculateFundingRate();

      expect(fundingRate).to.eq(
        virtualPrice
          .sub(realPrice)
          .mul(10 ** 6)
          .div(realPrice),
      );
    });
  });
});
