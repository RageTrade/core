//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import {TickUtilLib} from './TickUtilLib.sol';


library GlobalUtilLib {
    struct GlobalState {
        int256 sumB;
        int256 sumFP;
        uint256 lastTradeTS;
        int256 sumA;

        int16 fundingRate;

        uint256 feeGrowthGlobalShortsX128; // see if Binary Fixed point is needed or not
    }

    function getVirtualTwapPrice(uint256 diffTS) pure internal 
    returns(uint256){
        //TODO: Use vTokenLib
        return diffTS*1000;
    }

    function getExtrapolatedSumA(GlobalState storage global, uint256 currentTS) view public
    returns(int256) {
        uint256 diffTS = currentTS-global.lastTradeTS;
        return global.sumA + global.fundingRate*int(getVirtualTwapPrice(diffTS)*(diffTS));
    }

    function getExtrapolatedSumFP(GlobalState storage global, int256 sumACkpt, int256 sumBCkpt, int256 sumFPCkpt, uint256 currentTS) view public 
    returns (int256) {
        return sumFPCkpt + sumBCkpt *  getExtrapolatedSumA(global, currentTS) - sumACkpt;
    }

    //TODO:use vToken

    // function calculateFundingRate(VToken vToken) internal
    // returns(uint256) {
    //     uint64 vPrice = vToken.getVirtualTwapPrice();
    //     uint64 rPrice = vToken.getRealTwapPrice();

    //     return (vPrice/rPrice)-1;
    // }

    function updateOnTrade(GlobalState storage global, int256 b, uint256 feePerLiquidity) internal{
    //sumFP should be updated before updating sumB and lastTradeTS

        //TODO: block.timestamp is uint256 check
        uint256 curTS = block.timestamp;
        uint256 diffTS = curTS - global.lastTradeTS;

        //TODO: check if the conversion needs to be removed
        global.lastTradeTS = curTS;

        //TODO: Use vToken
        int256 a = 1000 ;//vToken.getVirtualTwapPrice(diffTS) * (diffTS) ;
        global.sumFP = global.sumFP + global.fundingRate *a* global.sumB; 
        global.sumA = global.sumA + a;
        global.sumB = global.sumB + b;

        global.feeGrowthGlobalShortsX128 += feePerLiquidity;
    }

    function getPricePosition(uint256 currentPrice, uint256 tickLowerPrice, uint256 tickHigherPrice) public
    returns(uint8){
        if(currentPrice<tickLowerPrice) return 0;
        else if(currentPrice<tickHigherPrice) return 1;
        else return 2;
    }

    function getUpdatedLPState(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, int256 sumFPInsideCkpt, uint256 currentTS) external view
    returns (int256,int256,int256,uint256){
        //TODO: Correct current price code
        // uint256 currentPrice = 1000;//getVirtualTwapPrice(timeHorizon);
        // uint256 tickLowerPrice =500;
        // uint256 tickHigherPrice = 1500;
        uint8 pricePosition = 0;//getPricePosition(currentPrice, tickLowerPrice, tickHigherPrice);

        int256 sumANew = getExtrapolatedSumA(global,currentTS);

        int256 exTickLowerFPOutside = getExtrapolatedSumFP(global,tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside,currentTS);
        int256 exTickHigherFPOutside = getExtrapolatedSumFP(global,tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside,currentTS);

        int256 sumBInsideNew; int256 sumFPInsideNew; uint256 shortsFeeInside;

        if(pricePosition==0){
            sumBInsideNew = tickLower.sumBOutside - tickHigher.sumBOutside;
            sumFPInsideNew = sumFPInsideCkpt + exTickLowerFPOutside - exTickHigherFPOutside;
            shortsFeeInside = tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128;
        }
        else if(pricePosition==1){
            sumBInsideNew = global.sumB - tickHigher.sumBOutside - tickLower.sumBOutside;
            sumFPInsideNew = sumFPInsideCkpt + global.sumFP - exTickLowerFPOutside - exTickHigherFPOutside;
            shortsFeeInside = tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128;
        }
        else if(pricePosition==2){
            sumBInsideNew = global.sumB - tickHigher.sumBOutside - tickLower.sumBOutside;
            sumFPInsideNew = global.sumFP - exTickHigherFPOutside - exTickLowerFPOutside;
            shortsFeeInside = global.feeGrowthGlobalShortsX128 - tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128;
        }

        return (sumANew, sumBInsideNew, sumFPInsideNew, shortsFeeInside);
    }

}
