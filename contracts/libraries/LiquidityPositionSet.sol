//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPosition } from './LiquidityPosition.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPositionSet {
    using LiquidityPositionSet for uint48[5];
    using Uint48L5ArrayLib for uint48[5];

    error IllegalTicks(int24 tickLower, int24 tickUpper);

    struct Info {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // TODO: consider instead of lpNonce, to use concat(int24,int24) then 5 positions can be stored
        // concat(tickLow,TickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
    }

    function isPositionActive(
        Info storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (bool) {
        return _exists(set.active, tickLower, tickUpper);
    }

    function getActivatedPosition(
        Info storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (LiquidityPosition.Info storage info) {
        if (tickLower > tickUpper) {
            revert IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = _include(set.active, tickLower, tickUpper);
        info = set.positions[positionId];

        if (info.tickLower != tickLower) {
            set.positions[positionId].tickLower = tickLower;
        }
        if (set.positions[positionId].tickUpper != tickUpper) {
            set.positions[positionId].tickUpper = tickUpper;
        }
    }

    function _include(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private returns (uint48 index) {
        array.include(index = Uint48Lib.concat(val1, val2));
    }

    function _exclude(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private returns (uint48 index) {
        array.exclude(index = Uint48Lib.concat(val1, val2));
    }

    function _exists(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private view returns (bool) {
        return array.exists(Uint48Lib.concat(val1, val2));
    }
}
