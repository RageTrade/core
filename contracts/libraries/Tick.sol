// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FundingPayment } from './FundingPayment.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

// extended tick state
library Tick {
    using VTokenLib for VTokenAddress;

    struct Info {
        int256 sumALastX128;
        int256 sumBOutsideX128;
        int256 sumFpOutsideX128;
        uint256 sumExFeeOutsideX128; // extended fee
    }

    function getExtendedTickStateInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        FundingPayment.Info memory fpGlobal,
        uint256 sumExFeeGlobalX128
    )
        internal
        view
        returns (
            int256 sumBInsideX128,
            int256 sumFpInsideX128,
            uint256 sumExFeeInsideX128
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
        uint256 sumExFeeBelowX128 = lower.sumExFeeOutsideX128;
        if (tickCurrent < tickLower) {
            sumBBelowX128 = fpGlobal.sumBX128 - sumBBelowX128;
            sumFpBelowX128 = fpGlobal.sumFpX128 - sumFpBelowX128;
            sumExFeeBelowX128 = sumExFeeGlobalX128 - sumExFeeBelowX128;
        }

        int256 sumBAboveX128 = upper.sumBOutsideX128;
        int256 sumFpAboveX128 = FundingPayment.extrapolatedSumFpX128(
            upper.sumALastX128,
            sumBAboveX128, // upper.sumBOutsideX128,
            upper.sumFpOutsideX128,
            fpGlobal.sumAX128
        );
        uint256 sumExFeeAboveX128 = upper.sumExFeeOutsideX128;
        if (tickCurrent >= tickUpper) {
            sumBAboveX128 = fpGlobal.sumBX128 - sumBAboveX128;
            sumFpAboveX128 = fpGlobal.sumFpX128 - sumFpAboveX128;
            sumExFeeAboveX128 = sumExFeeGlobalX128 - sumExFeeAboveX128;
        }

        sumBInsideX128 = fpGlobal.sumBX128 - sumBBelowX128 - sumBAboveX128;
        sumFpInsideX128 = fpGlobal.sumFpX128 - sumFpBelowX128 - sumFpAboveX128;
        sumExFeeInsideX128 = sumExFeeGlobalX128 - sumExFeeBelowX128 - sumExFeeAboveX128;
    }

    function getUniswapFeeGrowthInside(
        IUniswapV3Pool vPool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        bool isToken0
    ) internal view returns (uint256 uniswapFeeGrowthInsideX128) {
        uint256 uniswapFeeGrowthLowerX128;
        uint256 uniswapFeeGrowthUpperX128;
        {
            (, , uint256 fee0LowerX128, uint256 fee1LowerX128, , , , ) = vPool.ticks(tickLower);
            (, , uint256 fee0UpperX128, uint256 fee1UpperX128, , , , ) = vPool.ticks(tickUpper);
            if (isToken0) {
                uniswapFeeGrowthLowerX128 = fee1LowerX128;
                uniswapFeeGrowthUpperX128 = fee1UpperX128;
            } else {
                uniswapFeeGrowthLowerX128 = fee0LowerX128;
                uniswapFeeGrowthUpperX128 = fee0UpperX128;
            }
        }

        if (tickCurrent < tickLower) {
            uniswapFeeGrowthInsideX128 = uniswapFeeGrowthLowerX128 - uniswapFeeGrowthUpperX128;
        } else if (tickCurrent < tickUpper) {
            uniswapFeeGrowthInsideX128 = (isToken0 ? vPool.feeGrowthGlobal1X128() : vPool.feeGrowthGlobal0X128());
            uniswapFeeGrowthInsideX128 -= (uniswapFeeGrowthLowerX128 + uniswapFeeGrowthUpperX128);
        } else {
            uniswapFeeGrowthInsideX128 = uniswapFeeGrowthUpperX128 - uniswapFeeGrowthLowerX128;
        }
    }

    // function update(
    //     mapping(int24 => Tick.Info) storage self,
    //     int24 tick,
    //     int24 tickCurrent,
    //     uint256 sumExFeeGlobal0X128
    // ) internal returns (bool flipped) {
    //     // TODO if tick is flipped (when changing liquidity) then handle that case
    // }

    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        FundingPayment.Info memory fpGlobal,
        uint256 sumExFeeOutsideX128
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
        info.sumExFeeOutsideX128 = sumExFeeOutsideX128 - info.sumExFeeOutsideX128;
    }
}
