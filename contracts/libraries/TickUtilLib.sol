//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { GlobalUtilLib } from './GlobalUtilLib.sol';
import { Constants } from '../utils/Constants.sol';

library TickUtilLib {
    using GlobalUtilLib for GlobalUtilLib.GlobalState;

    struct TickState {
        int256 sumA;
        int256 sumBOutside;
        int256 sumFPOutside;
        uint256 feeGrowthOutsideShortsX128; // see if binary fixed point is needed
    }

    struct TickLowerHigher {
        TickState tickLower;
        TickState tickHigher;
    }

    function cross(
        TickState storage tick,
        GlobalUtilLib.GlobalState storage global,
        uint48 blockTimestamp,
        Constants memory constants
    ) internal {
        //sumFP should be updated before updating sumB and lastTradeTS
        tick.sumFPOutside =
            global.sumFP -
            global.getExtrapolatedSumFP(tick.sumA, tick.sumBOutside, tick.sumFPOutside, blockTimestamp, constants);
        tick.sumA = global.sumA; //Need not extrapolate because sumA would be updated just before tick cross based on remaining amount
        tick.sumBOutside = global.sumB - tick.sumBOutside;
        tick.feeGrowthOutsideShortsX128 = global.feeGrowthGlobalShortsX128 - tick.feeGrowthOutsideShortsX128;
    }
}
