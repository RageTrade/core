//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { PriceMath } from './PriceMath.sol';

import { console } from 'hardhat/console.sol';

library UniswapV3PoolHelper {
    using UniswapV3PoolHelper for IUniswapV3Pool;
    using PriceMath for uint160;

    error IllegalTwapDuration(uint32 period);
    error OracleConsultFailed();

    function tickCurrent(IUniswapV3Pool v3Pool) internal view returns (int24 tick) {
        (, tick, , , , , ) = v3Pool.slot0();
    }

    function sqrtPriceCurrent(IUniswapV3Pool v3Pool) internal view returns (uint160 sqrtPriceX96) {
        int24 tick;
        (sqrtPriceX96, tick, , , , , ) = v3Pool.slot0();
        // TODO remove this logic, fix the tests to make it work without the logic.
        if (sqrtPriceX96 == 0) {
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        }
    }

    function priceCurrent(IUniswapV3Pool v3Pool) internal view returns (uint256 priceX128) {
        uint160 sqrtPriceX96 = v3Pool.sqrtPriceCurrent();
        return sqrtPriceX96.toPriceX128();
    }

    function twapSqrtPrice(IUniswapV3Pool pool, uint32 twapDuration) internal view returns (uint160 sqrtPriceX96) {
        int24 _twapTick = pool.twapTick(twapDuration);
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_twapTick);
    }

    function twapTick(IUniswapV3Pool pool, uint32 twapDuration) internal view returns (int24 _twapTick) {
        if (twapDuration == 0) {
            revert IllegalTwapDuration(0);
        }

        uint32[] memory secondAgos = new uint32[](2);
        secondAgos[0] = twapDuration;
        secondAgos[1] = 0;

        // this call will fail if period is bigger than MaxObservationPeriod
        try pool.observe(secondAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(twapDuration)));

            // Always round to negative infinity
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(twapDuration)) != 0)) {
                timeWeightedAverageTick--;
            }
            return timeWeightedAverageTick;
        } catch {
            (, _twapTick, , , , , ) = pool.slot0();
        }
    }
}
