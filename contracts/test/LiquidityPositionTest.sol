//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';

import { console } from 'hardhat/console.sol';

contract LiquidityPositionTest {
    LiquidityPosition.Set liquidityPositions;

    function assertConcat(int24 val1, int24 val2) external pure returns (uint48 concatenated) {
        concatenated = concat(val1, val2);
        (int24 val1_, int24 val2_) = unconcat(concatenated);
        assert(val1_ == val1);
        assert(val2_ == val2);
    }

    function concat(int24 val1, int24 val2) public pure returns (uint48 concatenated) {
        concatenated = LiquidityPosition._concat(val1, val2);
    }

    function unconcat(uint48 concatenated) public pure returns (int24 val1, int24 val2) {
        assembly {
            val2 := concatenated
            val1 := shr(24, concatenated)
        }
    }
}
