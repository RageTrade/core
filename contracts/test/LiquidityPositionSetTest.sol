//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPositionSet, LiquidityPosition } from '../libraries/LiquidityPositionSet.sol';

import { console } from 'hardhat/console.sol';

contract LiquidityPositionSetTest {
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using LiquidityPosition for LiquidityPosition.Info;
    // using Uint48L5ArrayLib for uint48[5];

    LiquidityPositionSet.Info liquidityPositions;

    function isPositionActive(int24 tickLower, int24 tickUpper) public view returns (bool) {
        return liquidityPositions.isPositionActive(tickLower, tickUpper);
    }

    function createEmptyPosition(int24 tickLower, int24 tickUpper)
        external
        returns (LiquidityPosition.Info memory info)
    {
        info = liquidityPositions.getActivatedPosition(tickLower, tickUpper);
    }
}
