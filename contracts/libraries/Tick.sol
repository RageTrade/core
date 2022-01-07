// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FundingPayment } from './FundingPayment.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { LiquidityMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/LiquidityMath.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

// extended tick state
library Tick {
    using VTokenLib for VTokenAddress;

    struct Info {
        int256 sumALastX128;
        int256 sumBOutsideX128;
        int256 sumFpOutsideX128;
        uint256 sumFeeOutsideX128;
    }

    function getTickExtendedStateInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        FundingPayment.Info memory fpGlobal,
        uint256 sumFeeGlobalX128
    )
        internal
        view
        returns (
            int256 sumBInsideX128,
            int256 sumFpInsideX128,
            uint256 sumFeeInsideX128
        )
    {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        int256 sumBBelowX128 = lower.sumBOutsideX128;
        int256 sumFpBelowX128 = FundingPayment.extrapolatedSumFpX128(
            lower.sumALastX128,
            sumBBelowX128, // lower.sumBOutsideX128,
            lower.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        uint256 sumFeeBelowX128 = lower.sumFeeOutsideX128;
        if (tickLower > tickCurrent) {
            sumBBelowX128 = fpGlobal.sumBX128 - sumBBelowX128;
            sumFpBelowX128 = fpGlobal.sumFpX128 - sumFpBelowX128;
            sumFeeBelowX128 = sumFeeGlobalX128 - sumFeeBelowX128;
        }

        int256 sumBAboveX128 = upper.sumBOutsideX128;
        int256 sumFpAboveX128 = FundingPayment.extrapolatedSumFpX128(
            upper.sumALastX128,
            sumBAboveX128, // upper.sumBOutsideX128,
            upper.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        uint256 sumFeeAboveX128 = upper.sumFeeOutsideX128;
        if (tickUpper <= tickCurrent) {
            sumBAboveX128 = fpGlobal.sumBX128 - sumBAboveX128;
            sumFpAboveX128 = fpGlobal.sumFpX128 - sumFpAboveX128;
            sumFeeAboveX128 = sumFeeGlobalX128 - sumFeeAboveX128;
        }

        sumBInsideX128 = fpGlobal.sumBX128 - sumBBelowX128 - sumBAboveX128;
        sumFpInsideX128 = fpGlobal.sumFpX128 - sumFpBelowX128 - sumFpAboveX128;
        sumFeeInsideX128 = sumFeeGlobalX128 - sumFeeBelowX128 - sumFeeAboveX128;
    }

    function getUniswapFeeGrowthInside(
        IUniswapV3Pool vPool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) internal view returns (uint256 uniswapFeeGrowthInsideX128) {
        uint256 uniswapFeeGrowthLowerX128;
        uint256 uniswapFeeGrowthUpperX128;
        {
            (, , , uint256 fee1LowerX128, , , , ) = vPool.ticks(tickLower);
            (, , , uint256 fee1UpperX128, , , , ) = vPool.ticks(tickUpper);
            uniswapFeeGrowthLowerX128 = fee1LowerX128;
            uniswapFeeGrowthUpperX128 = fee1UpperX128;
        }

        if (tickCurrent < tickLower) {
            uniswapFeeGrowthInsideX128 = uniswapFeeGrowthLowerX128 - uniswapFeeGrowthUpperX128;
        } else if (tickCurrent < tickUpper) {
            uniswapFeeGrowthInsideX128 = vPool.feeGrowthGlobal1X128();
            uniswapFeeGrowthInsideX128 -= (uniswapFeeGrowthLowerX128 + uniswapFeeGrowthUpperX128);
        } else {
            uniswapFeeGrowthInsideX128 = uniswapFeeGrowthUpperX128 - uniswapFeeGrowthLowerX128;
        }
    }

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        int256 sumAGlobalX128,
        int256 sumBGlobalX128,
        int256 sumFpGlobalX128,
        uint256 sumFeeGlobal0X128,
        IUniswapV3Pool vPool
    ) internal returns (bool flipped) {
        // TODO if tick is flipped (when changing liquidity) then handle that case

        Tick.Info storage info = self[tick];

        (uint128 liquidityGrossBefore, , , , , , , ) = vPool.ticks(tick);
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                info.sumALastX128 = sumAGlobalX128;
                info.sumBOutsideX128 = sumBGlobalX128;
                info.sumFpOutsideX128 = sumFpGlobalX128;
                info.sumFeeOutsideX128 = sumFeeGlobal0X128;
            }
        }
    }

    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        FundingPayment.Info memory fpGlobal,
        uint256 sumFeeOutsideX128
    ) internal {
        Tick.Info storage info = self[tick];
        int256 sumFpOutsideX128 = FundingPayment.extrapolatedSumFpX128(
            info.sumALastX128,
            info.sumBOutsideX128,
            info.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        info.sumALastX128 = fpGlobal.sumAX128;
        info.sumBOutsideX128 = fpGlobal.sumBX128 - info.sumBOutsideX128;
        info.sumFpOutsideX128 = fpGlobal.sumFpX128 - sumFpOutsideX128;
        info.sumFeeOutsideX128 = sumFeeOutsideX128 - info.sumFeeOutsideX128;
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
        delete self[tick];
    }
}
