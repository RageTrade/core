//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { TickMath } from './uniswap/TickMath.sol';

library Oracle {
    using Oracle for IUniswapV3Pool;

    error IllegalTwapDuration(uint32 period);
    error OracleConsultFailed();

    function getTwapSqrtPrice(IUniswapV3Pool pool, uint32 twapDuration) internal view returns (uint160 sqrtPriceX96) {
        int24 twapTick = getTwapTick(pool, twapDuration);
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);
    }

    function getTwapTick(IUniswapV3Pool pool, uint32 twapDuration) internal view returns (int24) {
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
            revert OracleConsultFailed();
        }
    }
}
