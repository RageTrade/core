//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { console } from 'hardhat/console.sol';

contract LiquidityPositionTest {
    using LiquidityPosition for LiquidityPosition.Info;
    // using Uint48L5ArrayLib for uint48[5];

    LiquidityPosition.Info public lp;
    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function initialize(int24 tickLower, int24 tickUpper) external {
        lp.initialize(tickLower, tickUpper);
    }

    function updateCheckpoints() external {
        lp.update(wrapper);
    }

    function netPosition() public view returns (int256) {
        return lp.netPosition(wrapper);
    }

    event LiquidityChangeReturn(int256 vBaseIncrease, int256 vTokenIncrease, int256 traderPositionIncrease);

    function liquidityChange(int128 liquidity) public {
        (int256 vBaseIncrease, int256 vTokenIncrease, int256 traderPositionIncrease) = lp.liquidityChange(
            liquidity,
            wrapper
        );
        emit LiquidityChangeReturn(vBaseIncrease, vTokenIncrease, traderPositionIncrease);
    }
}
