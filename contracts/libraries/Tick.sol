// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import { FundingPayment } from './FundingPayment.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { console } from 'hardhat/console.sol';

// extended tick state
library Tick {
    using VTokenLib for VTokenAddress;

    struct Info {
        int256 sumALastX128;
        int256 sumBOutsideX128;
        int256 sumFpOutsideX128;
        uint256 extendedFeeGrowthOutsideX128; // extended fee for buys + sells
    }

    function getNetPositionInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        int256 sumBGlobalX128
    ) internal view returns (int256 netPositionGrowthX128) {
        if (tickCurrent < tickLower) {
            netPositionGrowthX128 = self[tickLower].sumBOutsideX128 - self[tickUpper].sumBOutsideX128;
        } else if (tickCurrent < tickUpper) {
            netPositionGrowthX128 = sumBGlobalX128 - self[tickLower].sumBOutsideX128 - self[tickUpper].sumBOutsideX128;
        } else {
            netPositionGrowthX128 = self[tickUpper].sumBOutsideX128 - self[tickLower].sumBOutsideX128;
        }
    }

    function getFundingPaymentGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        int256 sumAGlobalX128,
        int256 sumFpGlobalX128
    ) internal view returns (int256 fundingPaymentGrowthX128) {
        int256 fpOutsideLowerX128 = FundingPayment.extrapolatedSumFpX128(
            self[tickLower].sumALastX128,
            self[tickLower].sumBOutsideX128,
            self[tickLower].sumFpOutsideX128,
            sumAGlobalX128
        );

        int256 fpOutsideUpperX128 = FundingPayment.extrapolatedSumFpX128(
            self[tickUpper].sumALastX128,
            self[tickUpper].sumBOutsideX128,
            self[tickUpper].sumFpOutsideX128,
            sumAGlobalX128
        );

        if (tickCurrent < tickLower) {
            fundingPaymentGrowthX128 = fpOutsideLowerX128 - fpOutsideUpperX128;
        } else if (tickCurrent < tickUpper) {
            fundingPaymentGrowthX128 = sumFpGlobalX128 - fpOutsideLowerX128 - fpOutsideUpperX128;
        } else {
            fundingPaymentGrowthX128 = fpOutsideUpperX128 - fpOutsideLowerX128;
        }
    }

    function getUniswapFeeGrowthInside(
        IUniswapV3Pool vPool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        VTokenAddress vToken
    ) internal view returns (uint256 uniswapFeeGrowthInsideX128) {
        uint256 uniswapFeeGrowthLowerX128;
        uint256 uniswapFeeGrowthUpperX128;
        {
            (, , uint256 fee0LowerX128, uint256 fee1LowerX128, , , , ) = vPool.ticks(tickLower);
            (, , uint256 fee0UpperX128, uint256 fee1UpperX128, , , , ) = vPool.ticks(tickUpper);
            if (vToken.isToken0()) {
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
            uniswapFeeGrowthInsideX128 = (
                vToken.isToken0() ? vPool.feeGrowthGlobal1X128() : vPool.feeGrowthGlobal0X128()
            );
            uniswapFeeGrowthInsideX128 -= (uniswapFeeGrowthLowerX128 + uniswapFeeGrowthUpperX128);
        } else {
            uniswapFeeGrowthInsideX128 = uniswapFeeGrowthUpperX128 - uniswapFeeGrowthLowerX128;
        }
    }

    function getExtendedFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 extendedFeeGrowthGlobalX128
    ) internal view returns (uint256 extendedFeeGrowthInside) {
        if (tickCurrent < tickLower) {
            extendedFeeGrowthInside =
                self[tickLower].extendedFeeGrowthOutsideX128 -
                self[tickUpper].extendedFeeGrowthOutsideX128;
        } else if (tickCurrent < tickUpper) {
            extendedFeeGrowthInside =
                extendedFeeGrowthGlobalX128 -
                self[tickLower].extendedFeeGrowthOutsideX128 -
                self[tickUpper].extendedFeeGrowthOutsideX128;
        } else {
            extendedFeeGrowthInside =
                self[tickUpper].extendedFeeGrowthOutsideX128 -
                self[tickLower].extendedFeeGrowthOutsideX128;
        }
    }

    // function update(
    //     mapping(int24 => Tick.Info) storage self,
    //     int24 tick,
    //     int24 tickCurrent,
    //     uint256 extendedFeeGrowthGlobal0X128
    // ) internal returns (bool flipped) {
    //     // TODO if tick is flipped (when changing liquidity) then handle that case
    // }

    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        FundingPayment.Info memory fpGlobal,
        uint256 extendedFeeGrowthOutsideX128
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
        info.extendedFeeGrowthOutsideX128 = extendedFeeGrowthOutsideX128 - info.extendedFeeGrowthOutsideX128;
    }
}
