//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Tick } from '../libraries/Tick.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { UniswapV3PoolMock } from './mocks/UniswapV3PoolMock.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract TickTest {
    using Tick for mapping(int24 => Tick.Info);
    using Tick for IUniswapV3Pool;

    mapping(int24 => Tick.Info) public extendedTicks;

    IUniswapV3Pool public vPool;

    constructor() {
        vPool = IUniswapV3Pool(address(new UniswapV3PoolMock()));
    }

    function setTick(int24 tickIndex, Tick.Info memory tick) external {
        extendedTicks[tickIndex] = tick;
    }

    function getFundingPaymentGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        int256 sumAGlobal,
        int256 sumFpGlobal
    ) public view returns (int256 fundingPaymentGrowth) {
        return extendedTicks.getFundingPaymentGrowthInside(tickLower, tickUpper, tickCurrent, sumAGlobal, sumFpGlobal);
    }

    function getUniswapFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        VTokenAddress vToken
    ) public view returns (uint256 uniswapFeeGrowthInside) {
        return vPool.getUniswapFeeGrowthInside(tickLower, tickUpper, tickCurrent, vToken);
    }

    function getExtendedFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 extendedFeeGrowthGlobalX128
    ) public view returns (uint256 extendedFeeGrowthInside) {
        return extendedTicks.getExtendedFeeGrowthInside(tickLower, tickUpper, tickCurrent, extendedFeeGrowthGlobalX128);
    }
}
