//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SqrtPriceMath } from './uniswap/SqrtPriceMath.sol';
import { TickMath } from './uniswap/TickMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
import { Account } from './Account.sol';
import { FullMath } from './FullMath.sol';
import { VToken, VTokenLib } from './VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPosition {
    using FullMath for uint256;
    using LiquidityPosition for Info;
    using VTokenLib for VToken;

    error AlreadyInitialized();

    struct Info {
        // the tick range of the position; TODO Is storing ticks needed as it's in the positionId?
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // funding payment checkpoints
        int256 sumALast;
        int256 sumBInsideLast;
        int256 sumFpInsideLast;
        // the fee growth of the aggregate position as of the last action on the individual position
        // TODO since both of them are in vBase denomination, is a single fee var enough?
        // uint256 feeGrowthInsideLongsLastX128; // in uniswap's tick state
        // uint256 feeGrowthInsideShortsLastX128; // in wrapper's tick state
        uint256 longsFeeGrowthInsideLast;
        uint256 shortsFeeGrowthInsideLast;
    }

    function isInitialized(Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    function initialize(
        Info storage position,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        if (position.isInitialized()) {
            revert AlreadyInitialized();
        }

        position.tickLower = tickLower;
        position.tickUpper = tickUpper;
    }

    function liquidityChange(
        Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        (int256 vBaseIncrease, int256 vTokenIncrease) = wrapper.liquidityChange(
            position.tickLower,
            position.tickUpper,
            liquidity
        );
        balanceAdjustments.vBaseIncrease += vBaseIncrease;
        balanceAdjustments.vTokenIncrease += vTokenIncrease;

        position.update(wrapper, balanceAdjustments);

        if (liquidity > 0) {
            position.liquidity += uint128(liquidity);
        } else if (liquidity < 0) {
            position.liquidity -= uint128(liquidity * -1);
        }
    }

    function update(
        Info storage position,
        IVPoolWrapper wrapper, // TODO use vTokenLib
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        (
            int256 sumA,
            int256 sumBInside,
            int256 sumFpInside,
            uint256 longsFeeGrowthInside,
            uint256 shortsFeeGrowthInside
        ) = wrapper.getValuesInside(position.tickLower, position.tickUpper);

        balanceAdjustments.vBaseIncrease += position.unrealizedFundingPayment(sumA, sumFpInside);
        balanceAdjustments.traderPositionIncrease += position.netPosition(sumBInside);

        balanceAdjustments.vBaseIncrease += int256(
            position.unrealizedFees(longsFeeGrowthInside, shortsFeeGrowthInside)
        );

        // updating checkpoints
        position.sumALast = sumA;
        position.sumBInsideLast = sumBInside;
        position.sumFpInsideLast = sumFpInside;
        position.longsFeeGrowthInsideLast = longsFeeGrowthInside;
        position.shortsFeeGrowthInsideLast = shortsFeeGrowthInside;
    }

    function netPosition(Info storage position, IVPoolWrapper wrapper) internal view returns (int256) {
        (, int256 sumBInside, , , ) = wrapper.getValuesInside(position.tickLower, position.tickUpper);
        return position.netPosition(sumBInside);
    }

    function netPosition(Info storage position, int256 sumBInside) internal view returns (int256) {
        return (sumBInside - position.sumBInsideLast) * int128(position.liquidity);
    }

    function unrealizedFundingPayment(
        Info storage position,
        int256 sumA,
        int256 sumFpInside
    ) internal view returns (int256 vBaseIncrease) {
        vBaseIncrease = sumFpInside - (position.sumFpInsideLast + position.sumBInsideLast * (sumA - position.sumALast));
    }

    function unrealizedFees(
        Info storage position,
        uint256 longsFeeGrowthInside,
        uint256 shortsFeeGrowthInside
    ) internal view returns (uint256 vBaseIncrease) {
        vBaseIncrease = (longsFeeGrowthInside - position.longsFeeGrowthInsideLast) * position.liquidity;
        vBaseIncrease += (shortsFeeGrowthInside - position.shortsFeeGrowthInsideLast) * position.liquidity;
    }

    function maxNetPosition(Info storage position, VToken vToken) internal view returns (uint256) {
        uint160 priceLower = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(position.tickUpper);

        if (vToken.isToken0()) {
            return SqrtPriceMath.getAmount0Delta(priceLower, priceUpper, position.liquidity, true);
        } else {
            return SqrtPriceMath.getAmount1Delta(priceLower, priceUpper, position.liquidity, true);
        }
    }

    function baseValue(
        Info storage position,
        uint160 sqrtPriceCurrent,
        VToken vToken
    ) internal view returns (uint256) {
        uint160 priceLower = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(position.tickUpper);

        // If price is outside the range, then consider it at the ends
        // for calculation of amounts
        uint160 sqrtPriceMiddle = sqrtPriceCurrent;
        if (sqrtPriceCurrent < priceLower) {
            sqrtPriceMiddle = priceLower;
        } else if (sqrtPriceCurrent > priceUpper) {
            sqrtPriceMiddle = priceUpper;
        }

        uint256 baseAmount = SqrtPriceMath.getAmount0Delta(priceLower, sqrtPriceMiddle, position.liquidity, false);
        uint256 vTokenAmount = SqrtPriceMath.getAmount1Delta(sqrtPriceMiddle, priceUpper, position.liquidity, false);
        if (vToken.isToken0()) {
            (baseAmount, vTokenAmount) = (vTokenAmount, baseAmount);
            sqrtPriceCurrent = uint160(FixedPoint96.Q96.mulDiv(FixedPoint96.Q96, sqrtPriceCurrent)); // TODO safe reprocate the price
        }

        return (baseAmount +
            vTokenAmount.mulDiv(sqrtPriceCurrent, FixedPoint96.Q96).mulDiv(sqrtPriceCurrent, FixedPoint96.Q96));
    }
}
