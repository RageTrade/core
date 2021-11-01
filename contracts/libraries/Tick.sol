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
        int256 sumALast;
        int256 sumBOutside;
        int256 sumFpOutside;
        uint256 extendedFeeGrowthOutsideX128; // extended fee for buys + sells
    }

    function getFundingPaymentGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        int256 sumAGlobal,
        int256 sumFpGlobal
    ) internal view returns (int256 fundingPaymentGrowth) {
        int256 fpOutsideLower = FundingPayment.extrapolatedSumFp(
            self[tickLower].sumALast,
            self[tickLower].sumBOutside,
            self[tickLower].sumFpOutside,
            sumAGlobal
        );

        int256 fpOutsideUpper = FundingPayment.extrapolatedSumFp(
            self[tickUpper].sumALast,
            self[tickUpper].sumBOutside,
            self[tickUpper].sumFpOutside,
            sumAGlobal
        );

        if (tickCurrent < tickLower) {
            fundingPaymentGrowth = fpOutsideLower - fpOutsideUpper;
        } else if (tickLower <= tickCurrent && tickCurrent < tickUpper) {
            fundingPaymentGrowth = sumFpGlobal - fpOutsideLower - fpOutsideUpper;
        } else {
            fundingPaymentGrowth = fpOutsideUpper - fpOutsideLower;
        }
    }

    function getUniswapFeeGrowthInside(
        IUniswapV3Pool vPool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        VTokenAddress vToken
    ) internal view returns (uint256 uniswapFeeGrowthInside) {
        uint256 uniswapFeeGrowthLower;
        uint256 uniswapFeeGrowthUpper;
        {
            (, , uint256 fee0Lower, uint256 fee1Lower, , , , ) = vPool.ticks(tickLower);
            (, , uint256 fee0Upper, uint256 fee1Upper, , , , ) = vPool.ticks(tickUpper);
            if (vToken.isToken0()) {
                uniswapFeeGrowthLower = fee1Lower;
                uniswapFeeGrowthUpper = fee1Upper;
            } else {
                uniswapFeeGrowthLower = fee0Lower;
                uniswapFeeGrowthUpper = fee0Upper;
            }
        }

        if (tickCurrent < tickLower) {
            uniswapFeeGrowthInside = uniswapFeeGrowthLower - uniswapFeeGrowthUpper;
        } else if (tickLower <= tickCurrent && tickCurrent < tickUpper) {
            uniswapFeeGrowthInside = (vToken.isToken0() ? vPool.feeGrowthGlobal1X128() : vPool.feeGrowthGlobal0X128());
            uniswapFeeGrowthInside -= (uniswapFeeGrowthLower + uniswapFeeGrowthUpper);
        } else {
            uniswapFeeGrowthInside = uniswapFeeGrowthUpper - uniswapFeeGrowthLower;
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
        } else if (tickLower <= tickCurrent && tickCurrent < tickUpper) {
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

    // add tick cross method
}
