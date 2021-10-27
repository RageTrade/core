import { expect } from 'chai';
import { BigNumber } from 'ethers';
import hre from 'hardhat';

import { GlobalUtilLibTest } from '../typechain';

const fundingRateNormalizer = BigNumber.from(10000*100*3600);
const fixedMathMultiplier = BigNumber.from(10**12);


function getExtrapolatedSumA(globalSumA:BigNumber,globalFundingRate:BigNumber,lastTS:BigNumber,globalLastTradeTS:BigNumber,price:BigNumber){
  return globalSumA.add((globalFundingRate.mul(price).mul(lastTS.sub(globalLastTradeTS))).div(fundingRateNormalizer));
}
function getExtrapolatedSumFP(sumACkpt:BigNumber,sumBCkpt:BigNumber,sumFPCkpt:BigNumber,globalSumA:BigNumber,globalFundingRate:BigNumber,lastTS:BigNumber,globalLastTradeTS:BigNumber,price:BigNumber){
  return sumFPCkpt.add(sumBCkpt.mul(getExtrapolatedSumA(globalSumA,globalFundingRate,lastTS,globalLastTradeTS,price).sub(sumACkpt)));
}
describe('Tick Util Library', () => {
  let test: GlobalUtilLibTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('GlobalUtilLibTest');
    test = await factory.deploy();
  });

  describe('Extrapolation', () => {
    it('SumA Extrapolation', async () => {
        
        const globalSumA = BigNumber.from(30);
        const globalSumB = BigNumber.from(150);
        const globalSumFP = BigNumber.from(1000);
        const globalLastTradeTS = BigNumber.from(0);
        const globalFundingRate = BigNumber.from(1);
        const globalFeeGrowthGlobalShortsX128 = BigNumber.from(50);
        const price = BigNumber.from(4000);

        await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
            globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);

        const out = await test.getExtrapolatedSumA();

        const extrapolatedSumA = out[0];
        const lastTS = BigNumber.from(out[1]);
        
        expect(extrapolatedSumA).to.eq(getExtrapolatedSumA(globalSumA,globalFundingRate,lastTS,globalLastTradeTS,price));

    });

    it('SumFP Extrapolation', async () => {

      const tickLowerSumA = BigNumber.from(20);
      const tickLowerSumBOutside = BigNumber.from(30);
      const tickLowerSumFPOutside = BigNumber.from(500);
      const tickLowerFeeGrowthOutsideShortsX128 = BigNumber.from(10);
      const tickLowerIndex = BigNumber.from(500);
      
      const tickHigherSumA = BigNumber.from(20);
      const tickHigherSumBOutside = BigNumber.from(30);
      const tickHigherSumFPOutside = BigNumber.from(500);
      const tickHigherFeeGrowthOutsideShortsX128 = BigNumber.from(10);
      const tickHigherIndex = BigNumber.from(1500);
      
      const globalSumA = BigNumber.from(30);
      const globalSumB = BigNumber.from(150);
      const globalSumFP = BigNumber.from(1000);
      const globalLastTradeTS = BigNumber.from(0);
      const globalFundingRate = BigNumber.from(10);
      const globalFeeGrowthGlobalShortsX128 = BigNumber.from(50);

      const price = BigNumber.from(4000);
      
      const sumACkpt = BigNumber.from(1);
      const sumBCkpt = BigNumber.from(5);
      const sumFPCkpt = BigNumber.from(100);

      
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
        tickHigherIndex);

      await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
          globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);
          
      const out = await test.getExtrapolatedSumFP(sumACkpt,sumBCkpt,sumFPCkpt);

      const extrapolatedSumFP = out[0];
      const lastTS = BigNumber.from(out[1]);

      expect(extrapolatedSumFP).to.eq(getExtrapolatedSumFP(sumACkpt,sumBCkpt,sumFPCkpt,globalSumA,globalFundingRate,lastTS,globalLastTradeTS,price));


  });
  });

  describe('Trade Update', () => {
    it('Check #1', async () => {
        
        const globalSumA = BigNumber.from(30);
        const globalSumB = BigNumber.from(150);
        const globalSumFP = BigNumber.from(1000);
        const globalLastTradeTS = BigNumber.from(0);
        const globalFundingRate = BigNumber.from(10);
        const globalFeeGrowthGlobalShortsX128 = BigNumber.from(50);
        
        const tradeB = BigNumber.from(1);
        const feePerLiquidity = BigNumber.from(1);

        const price = BigNumber.from(4000);

        await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
            globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);

        await test.simulateUpdateOnTrade(tradeB,feePerLiquidity);
        const lastTS = BigNumber.from(await test.getBlockTimeStamp());

        const global = await test.global();

        const a = price.mul(lastTS.sub(globalLastTradeTS));

        expect(global.sumA).to.eq(globalSumA.add(a));
        expect(global.sumB).to.eq(globalSumB.add(tradeB));
        expect(global.sumFP).to.eq(globalSumFP.add((globalFundingRate.mul(a).mul(globalSumB)).div(fundingRateNormalizer)));
        expect(global.feeGrowthGlobalShortsX128).to.eq(globalFeeGrowthGlobalShortsX128.add(feePerLiquidity));



    });

  });

  describe('LP State Update', () => {
    it('Check #1', async () => {
        
      
        const tickLowerSumA = 20;
        const tickLowerSumBOutside = 30;
        const tickLowerSumFPOutside = 500;
        const tickLowerFeeGrowthOutsideShortsX128 = 10;
        const tickLowerIndex = 500;

        const tickHigherSumA = 20;
        const tickHigherSumBOutside = 30;
        const tickHigherSumFPOutside = 500;
        const tickHigherFeeGrowthOutsideShortsX128 = 10;
        const tickHigherIndex = 1500;

        const globalSumA = 30;
        const globalSumB = 150;
        const globalSumFP = 1000;
        const globalLastTradeTS = 0;
        const globalFundingRate = 10;
        const globalFeeGrowthGlobalShortsX128 = 50;

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
          tickHigherIndex);

        await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
            globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);

        // const lpState = await test.getUpdatedLPState();
        
        // const lpStateSumA = lpState[0];
        // const lpStateSumB = lpState[1];
        // const lpStateSumFP = lpState[2];
        // const lpStateFees = lpState[3];

        // expect(lpStateSumA).to.eq(getExtrapolatedSumA(globalSumA,globalFundingRate,lastTS));
        // expect(tick.sumA).to.eq(globalSumA);
        // expect(tick.sumBOutside).to.eq(globalSumB-tickSumBOutside);
        // expect(tick.sumA).to.eq(globalSumA+globalFundingRate*simulationTS*1000*simulationTS);
        // expect(tick.feeGrowthOutsideShortsX128).to.eq(globalFeeGrowthGlobalShortsX128-tickFeeGrowthOutsideShortsX128);


    });

  });
});
