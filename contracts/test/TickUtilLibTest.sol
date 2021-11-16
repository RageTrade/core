//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TickUtilLib } from '../libraries/TickUtilLib.sol';
import { GlobalUtilLib } from '../libraries/GlobalUtilLib.sol';

import { console } from 'hardhat/console.sol';
import { Constants } from '../Constants.sol';

contract TickUtilLibTest {
    using TickUtilLib for TickUtilLib.TickState;
    using GlobalUtilLib for GlobalUtilLib.GlobalState;

    // using Uint48L5ArrayLib for uint48[5];

    TickUtilLib.TickState public tick;
    GlobalUtilLib.GlobalState public global;

    uint48 public blockTimestamp;

    function initializeTickState(
        int256 sumA,
        int256 sumBOutside,
        int256 sumFPOutside,
        uint256 feeGrowthOutsideShortsX128
    ) external {
        tick.sumA = sumA;
        tick.sumBOutside = sumBOutside;
        tick.sumFPOutside = sumFPOutside;
        tick.feeGrowthOutsideShortsX128 = feeGrowthOutsideShortsX128;
    }

    function initializeGlobalState(
        int256 sumA,
        int256 sumB,
        int256 sumFP,
        uint48 lastTradeTS,
        int16 fundingRate,
        uint256 feeGrowthGlobalShortsX128
    ) external {
        global.sumB = sumB;
        global.sumFP = sumFP;
        global.lastTradeTS = lastTradeTS;
        global.sumA = sumA;
        global.fundingRate = fundingRate;
        global.feeGrowthGlobalShortsX128 = feeGrowthGlobalShortsX128;
    }

    function setBlockTimestamp(uint48 _blockTimestamp) external {
        blockTimestamp = _blockTimestamp;
    }

    function getBlockTimestamp() external view returns (uint48) {
        return blockTimestamp;
    }

    function simulateCross(Constants memory constants) external {
        tick.cross(global, blockTimestamp, constants);
    }
}
