//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import {TickUtilLib} from './TickUtilLib.sol';


library GlobalUtilLib {
    using GlobalUtilLib for GlobalState;
    int256 constant fundingRateNormalizer = 10000*100*3600; 

    struct GlobalState {
        int256 sumB;
        int256 sumFP;
        uint48 lastTradeTS;
        int256 sumA;

        int16 fundingRate; // (funding rate/hr in %) * 10000

        uint256 feeGrowthGlobalShortsX128; // see if Binary Fixed point is needed or not
    }

    function getVirtualTwapPrice(uint256 diffTS) pure internal 
    returns(uint256){
        //TODO: Use vTokenLib
        return 4000;
    }

    function getExtrapolatedSumA(GlobalState storage global) view internal
    returns(int256) {
        uint48 curTS = uint48(block.timestamp);
        uint48 diffTS = curTS-global.lastTradeTS;
        return global.sumA + (global.fundingRate*int(getVirtualTwapPrice(diffTS)*(diffTS)))/fundingRateNormalizer;
    }

    function getExtrapolatedSumFP(GlobalState storage global, int256 sumACkpt, int256 sumBCkpt, int256 sumFPCkpt) view internal 
    returns (int256) {
        return sumFPCkpt + sumBCkpt *  (global.getExtrapolatedSumA() - sumACkpt);
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
        uint48 curTS = uint48(block.timestamp);
        uint48 diffTS = curTS - global.lastTradeTS;

        //TODO: check if the conversion needs to be removed
        global.lastTradeTS = curTS;

        //TODO: Use vToken
        int256 a = int256(getVirtualTwapPrice(diffTS))*int48(diffTS);//vToken.getVirtualTwapPrice(diffTS) * (diffTS) ;
        global.sumFP = global.sumFP + (global.fundingRate *a* global.sumB)/fundingRateNormalizer; 
        global.sumA = global.sumA + a;
        global.sumB = global.sumB + b;

        global.feeGrowthGlobalShortsX128 += feePerLiquidity;
    }

    function getPricePosition(int24 curPriceIndex, int24 tickLowerIndex, int24 tickHigherIndex) pure internal
    returns(uint8){
        if(curPriceIndex<tickLowerIndex) return 0;
        else if(curPriceIndex<tickHigherIndex) return 1;
        else return 2;
    }

    // function getSumBInside(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, uint8 pricePosition) internal view
    // returns (int256){
    //     if(pricePosition==0){
    //         return tickLower.sumBOutside - tickHigher.sumBOutside;
    //     } else if( pricePosition==1){
    //         return global.sumB - tickHigher.sumBOutside - tickLower.sumBOutside;
    //     } else {
    //         return tickHigher.sumBOutside - tickLower.sumBOutside;
    //     }
    // }

    // function getSumFPInside(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, uint8 pricePosition) internal view
    // returns (int256){
    //     if(pricePosition==0){
    //         return global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside) - global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside);
    //     } else if( pricePosition==1){
    //         return global.sumFP - global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside) - global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside);
    //     } else {
    //         return global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside) - global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside);
    //     }
    // }

    // function getFeesShortsInside(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, uint8 pricePosition) internal view
    // returns (uint256){
    //     if(pricePosition==0){
    //         return tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128;
    //     } else if( pricePosition==1){
    //         return global.feeGrowthGlobalShortsX128 - tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128;
    //     } else {
    //         return tickHigher.feeGrowthOutsideShortsX128 - tickLower.feeGrowthOutsideShortsX128;
    //     }
    // }

    function getUpdatedLPStateInternal(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, uint8 pricePosition) internal view
    returns (int256,int256,int256,uint256){
        // return( 
        //     global.getExtrapolatedSumA(),
        //     global.getSumBInside(tickLower,tickHigher,pricePosition),
        //     global.getSumFPInside(tickLower, tickHigher,pricePosition),
        //     global.getFeesShortsInside(tickLower,tickHigher,pricePosition)
        //     );  

        if(pricePosition==0){
            return(
                global.getExtrapolatedSumA(),
                tickLower.sumBOutside - tickHigher.sumBOutside,
                global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside) - global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside),
                tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128
                );
        }
        else if(pricePosition==1){
            return(
                global.getExtrapolatedSumA(),
                global.sumB - tickHigher.sumBOutside - tickLower.sumBOutside,
                global.sumFP - global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside) - global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside),
                global.feeGrowthGlobalShortsX128 - tickLower.feeGrowthOutsideShortsX128 - tickHigher.feeGrowthOutsideShortsX128
                );
        }
        else {
            return(
                global.getExtrapolatedSumA(),
                tickHigher.sumBOutside - tickLower.sumBOutside,
                global.getExtrapolatedSumFP(tickHigher.sumA,tickHigher.sumBOutside,tickHigher.sumFPOutside) - global.getExtrapolatedSumFP(tickLower.sumA,tickLower.sumBOutside,tickLower.sumFPOutside),
                tickHigher.feeGrowthOutsideShortsX128 - tickLower.feeGrowthOutsideShortsX128
                );

        }

    }

    //SumFP Ckpt removed because of stack too deep. Can be added outside.
    function getUpdatedLPState(GlobalState storage global, TickUtilLib.TickState storage tickLower, TickUtilLib.TickState storage tickHigher, int24 tickLowerIndex, int24 tickHigherIndex) internal view
    returns (int256,int256,int256,uint256){
        //TODO: Correct current price code
        int24 curPriceIndex = 1000;//getVirtualTwapPrice(timeHorizon);
        uint8 pricePosition = getPricePosition(curPriceIndex,tickLowerIndex,tickHigherIndex);
        
        return global.getUpdatedLPStateInternal(tickLower,tickHigher,pricePosition);
    }

}
