//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint48L5ArrayLib } from './Uint48L5Array.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPosition {
    using Uint48L5ArrayLib for uint48[5];

    error IllegalTicks(int24 tickLower, int24 tickUpper);

    struct Set {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // TODO: consider instead of lpNonce, to use concat(int24,int24) then 5 positions can be stored
        // concat(tickLow,TickHigh)
        mapping(uint48 => Info) infos;
    }

    struct Info {
        // the tick range of the position
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInsideLongsLastX128; // in uniswap's tick state
        uint256 feeGrowthInsideShortsLastX128; // in wrapper's tick state
        // funding payment checkpoints
        uint256 sumAChkpt;
        uint256 sumBInsideChkpt;
        uint256 sumFpInsideChkpt;
    }

    function getActivatedPosition(
        Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (Info storage info) {
        if (tickLower > tickUpper) {
            revert IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = set.active.include(tickLower, tickUpper);
        info = set.infos[positionId];

        if (info.tickLower != tickLower) {
            set.infos[positionId].tickLower = tickLower;
        }
        if (set.infos[positionId].tickUpper != tickUpper) {
            set.infos[positionId].tickUpper = tickUpper;
        }
    }

    // function getMaxTokenPosition(info) {}

    // function getLiquidityPositionValue(info, sqrtPriceCurrent) returns (int96) {}

    // function netPosition(Info info) {}

    // function realizeFundingPayment(Set storage set, account) internal {}

    // function liquidityChange(
    //     Set storage set,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidity
    // ) internal returns (uint256 vBaseBalanceChange, uint256 vTokenBalanceChange) {}
}
