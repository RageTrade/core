//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TickUtilLib } from '../libraries/TickUtilLib.sol';
import { GlobalUtilLib } from '../libraries/GlobalUtilLib.sol';

import { console } from 'hardhat/console.sol';

contract GlobalUtilLibTest {
    using TickUtilLib for TickUtilLib.TickState;
    using GlobalUtilLib for GlobalUtilLib.GlobalState;

    // using Uint48L5ArrayLib for uint48[5];

    int24 tickLowerIndex;
    int24 tickHigherIndex;

    TickUtilLib.TickState public tickLower;
    TickUtilLib.TickState public tickHigher;

    GlobalUtilLib.GlobalState public global;
    uint48 public lastTS;

    function initializeTickState(int256 tickLowerSumA, int256 tickLowerSumBOutside, int256 tickLowerSumFPOutside, uint256 tickLowerFeeGrowthOutsideShortsX128, int24 tickLowerIndex,
    int256 tickHigherSumA, int256 tickHigherSumBOutside, int256 tickHigherSumFPOutside, uint256 tickHigherFeeGrowthOutsideShortsX128, int24 tickHigherIndex) external {
        tickLower.sumA = tickLowerSumA;
        tickLower.sumBOutside = tickLowerSumBOutside;
        tickLower.sumFPOutside  = tickLowerSumFPOutside;
        tickLower.feeGrowthOutsideShortsX128 = tickLowerFeeGrowthOutsideShortsX128;
        tickLowerIndex = tickLowerIndex; 

        tickHigher.sumA = tickHigherSumA;
        tickHigher.sumBOutside = tickHigherSumBOutside;
        tickHigher.sumFPOutside  = tickHigherSumFPOutside;
        tickHigher.feeGrowthOutsideShortsX128 = tickHigherFeeGrowthOutsideShortsX128;
        tickHigherIndex = tickHigherIndex; 
        
    }

    function initializeGlobalState(int256 sumA, int256 sumB, int256 sumFP, uint48 lastTradeTS, int16 fundingRate, uint256 feeGrowthGlobalShortsX128) external {
        global.sumB = sumB;
        global.sumFP = sumFP;
        global.lastTradeTS = lastTradeTS;
        global.sumA = sumA;
        global.fundingRate = fundingRate;
        global.feeGrowthGlobalShortsX128 = feeGrowthGlobalShortsX128;
    }

    function getExtrapolatedSumA() external view returns(int256,uint48) {
        return (global.getExtrapolatedSumA(),uint48(block.timestamp));
    }

    function getBlockTimeStamp() external view returns(uint48){
        return uint48(block.timestamp);
    }

    function getExtrapolatedSumFP(int256 sumACkpt, int256 sumBCkpt, int256 sumFPCkpt) external view returns(int256,uint48) {
        return (global.getExtrapolatedSumFP(sumACkpt,sumBCkpt,sumFPCkpt),uint48(block.timestamp));
    }

    function simulateUpdateOnTrade(int256 b, uint256 feePerLiquidity) external {
        global.updateOnTrade(b, feePerLiquidity);
    }

    function getUpdatedLPState() external view returns(int256,int256,int256,uint256){
        return global.getUpdatedLPState(tickLower, tickHigher, tickLowerIndex, tickHigherIndex);
    }
}
