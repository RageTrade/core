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

  describe('#TimeDelay', () => {
    it('Increase Time', async () => {

        const diffTS = 3000;
        const startTS = await test.getBlockTimestamp();
        hre.ethers.provider.send('evm_increaseTime', [diffTS]);
        await test.simulateCross();
        const endTS = await test.getBlockTimestamp();

        const finalDiffTS = endTS-startTS;

        expect(finalDiffTS).to.eq(diffTS);

    });
  });


  describe('#TickCross', () => {
    it('TickCross #1', async () => {

        var diffTS = BigNumber.from(5000);

        const price = BigNumber.from(4000);

        const tickSumA = BigNumber.from(20);
        const tickSumBOutside = BigNumber.from(1);
        const tickSumFPOutside = BigNumber.from(50);
        const tickFeeGrowthOutsideShortsX128 = BigNumber.from(10);
        
        const globalSumA = BigNumber.from(30);
        const globalSumB = BigNumber.from(150);
        const globalSumFP = BigNumber.from(100);
        const globalLastTradeTS = BigNumber.from(await test.getBlockTimestamp());
        const globalFundingRate = BigNumber.from(5000);
        const globalFeeGrowthGlobalShortsX128 = BigNumber.from(50);
        
        await test.initializeTickState(tickSumA,tickSumBOutside,tickSumFPOutside,
            tickFeeGrowthOutsideShortsX128);
        await test.initializeGlobalState(globalSumA,globalSumB,globalSumFP,
            globalLastTradeTS,globalFundingRate,globalFeeGrowthGlobalShortsX128);
        
        //Subtracting 2 to adjust for extra delay coming in the test
        hre.ethers.provider.send('evm_increaseTime', [diffTS.toNumber()-2]);
        await test.simulateCross();


        const simulationTS = BigNumber.from(await test.getBlockTimestamp());

        const tick = await test.tick();

        const updatedSumFPOutside = globalSumFP.sub(getExtrapolatedSumFP(tickSumA,tickSumBOutside,tickSumFPOutside,globalSumA,globalFundingRate,simulationTS,globalLastTradeTS,price));
        console.log("updatedSumFPOutside: ",updatedSumFPOutside.toNumber());

        expect(simulationTS.sub(globalLastTradeTS)).to.eq(diffTS);
        expect(tick.sumA).to.eq(globalSumA);
        expect(tick.sumBOutside).to.eq(globalSumB.sub(tickSumBOutside));
        expect(tick.sumFPOutside).to.eq(updatedSumFPOutside);
        expect(tick.feeGrowthOutsideShortsX128).to.eq(globalFeeGrowthGlobalShortsX128.sub(tickFeeGrowthOutsideShortsX128));


    });
  });
});
