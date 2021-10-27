import { expect } from 'chai';
import { BigNumber } from 'ethers';
import hre from 'hardhat';

import { TickUtilLibTest } from '../typechain';

const fundingRateNormalizer = BigNumber.from(10000*100*3600);
const fixedMathMultiplier = BigNumber.from(10**12);


function getExtrapolatedSumA(globalSumA:BigNumber,globalFundingRate:BigNumber,lastTS:BigNumber,globalLastTradeTS:BigNumber,price:BigNumber){
  return globalSumA.add((globalFundingRate.mul(price).mul(lastTS.sub(globalLastTradeTS))).div(fundingRateNormalizer));
}
function getExtrapolatedSumFP(sumACkpt:BigNumber,sumBCkpt:BigNumber,sumFPCkpt:BigNumber,globalSumA:BigNumber,globalFundingRate:BigNumber,lastTS:BigNumber,globalLastTradeTS:BigNumber,price:BigNumber){
  return sumFPCkpt.add(sumBCkpt.mul(getExtrapolatedSumA(globalSumA,globalFundingRate,lastTS,globalLastTradeTS,price).sub(sumACkpt)));
}

describe('Tick Util Library', () => {
  let test: TickUtilLibTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('TickUtilLibTest');
    test = await factory.deploy();
  });

  describe('#TickCross', () => {
    it('TickCross #1', async () => {

        const startTS = BigNumber.from(5000);
        const endTS = BigNumber.from(10000); 

        const price = BigNumber.from('4000000000000000000000');

        const tickSumA = BigNumber.from('20000000000000000000');
        const tickSumBOutside = BigNumber.from('1000000000000000000');
        const tickSumFPOutside = BigNumber.from('50000000000000000000');
        const tickFeeGrowthOutsideShortsX128 = BigNumber.from('10000000000000000000');
        
        const globalSumA = BigNumber.from('30000000000000000000');
        const globalSumB = BigNumber.from('150000000000000000000');
        const globalSumFP = BigNumber.from('100000000000000000000');
        const globalLastTradeTS = startTS;
        const globalFundingRate = BigNumber.from(5000);
        const globalFeeGrowthGlobalShortsX128 = BigNumber.from('50000000000000000000');
        
        await test.initializeTickState(tickSumA,tickSumBOutside,tickSumFPOutside,
            tickFeeGrowthOutsideShortsX128);
        await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
            globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);
        
        await test.setBlockTimestamp(endTS);
        await test.simulateCross();

        const tick = await test.tick();

        const updatedSumFPOutside = globalSumFP.sub(getExtrapolatedSumFP(tickSumA,tickSumBOutside,tickSumFPOutside,globalSumA,globalFundingRate,endTS,globalLastTradeTS,price));

        expect(tick.sumA).to.eq(globalSumA);
        expect(tick.sumBOutside).to.eq(globalSumB.sub(tickSumBOutside));
        expect(tick.sumFPOutside).to.eq(updatedSumFPOutside);
        expect(tick.feeGrowthOutsideShortsX128).to.eq(globalFeeGrowthGlobalShortsX128.sub(tickFeeGrowthOutsideShortsX128));


    });
  });
});
