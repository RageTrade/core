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

    // TickUtilLib.TickState public tickLower;
    // TickUtilLib.TickState public tickHigher;

    TickUtilLib.TickLowerHigher public tickLowerHigher;

    GlobalUtilLib.GlobalState public global;
    uint48 blockTimestamp;

    function initializeTickState(int256 tickLowerSumA, int256 tickLowerSumBOutside, int256 tickLowerSumFPOutside, uint256 tickLowerFeeGrowthOutsideShortsX128, int24 _tickLowerIndex,
    int256 tickHigherSumA, int256 tickHigherSumBOutside, int256 tickHigherSumFPOutside, uint256 tickHigherFeeGrowthOutsideShortsX128, int24 _tickHigherIndex) external {
        tickLowerHigher.tickLower.sumA = tickLowerSumA;
        tickLowerHigher.tickLower.sumBOutside = tickLowerSumBOutside;
        tickLowerHigher.tickLower.sumFPOutside  = tickLowerSumFPOutside;
        tickLowerHigher.tickLower.feeGrowthOutsideShortsX128 = tickLowerFeeGrowthOutsideShortsX128;
        
        tickLowerIndex = _tickLowerIndex; 
        
        tickLowerHigher.tickHigher.sumA = tickHigherSumA;
        tickLowerHigher.tickHigher.sumBOutside = tickHigherSumBOutside;
        tickLowerHigher.tickHigher.sumFPOutside  = tickHigherSumFPOutside;
        tickLowerHigher.tickHigher.feeGrowthOutsideShortsX128 = tickHigherFeeGrowthOutsideShortsX128;
        
        tickHigherIndex = _tickHigherIndex; 
        
    }

    function initializeGlobalState(int256 sumA, int256 sumB, int256 sumFP, uint48 lastTradeTS, int16 fundingRate, uint256 feeGrowthGlobalShortsX128) external {
        global.sumB = sumB;
        global.sumFP = sumFP;
        global.lastTradeTS = lastTradeTS;
        global.sumA = sumA;
        global.fundingRate = fundingRate;
        global.feeGrowthGlobalShortsX128 = feeGrowthGlobalShortsX128;
    }

    function getExtrapolatedSumA() external view returns(int256) {
        return (global.getExtrapolatedSumA(blockTimestamp));
    }

    function setBlockTimestamp(uint48 _blockTimestamp) external {
        blockTimestamp = _blockTimestamp;
    }

    function getBlockTimestamp() external view returns(uint48){
        return blockTimestamp;
    }

    function getPricePosition(int24 curPriceIndex) external view returns(uint8){
        return GlobalUtilLib.getPricePosition(curPriceIndex,tickLowerIndex,tickHigherIndex);
    }

    function getExtrapolatedSumFP(int256 sumACkpt, int256 sumBCkpt, int256 sumFPCkpt) external view returns(int256) {
        return (global.getExtrapolatedSumFP(sumACkpt,sumBCkpt,sumFPCkpt,blockTimestamp));
    }

    function simulateUpdateOnTrade(int256 tokenAmount, uint256 fees, uint256 liquidity) external {
        global.updateOnTrade(tokenAmount, fees, liquidity, blockTimestamp);
    }

    function getUpdatedLPState() external view returns(int256,int256,int256,uint256){
        return global.getUpdatedLPState(tickLowerHigher, tickLowerIndex, tickHigherIndex,blockTimestamp);
    }
}
