//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SqrtPriceMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/SqrtPriceMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { Account } from './Account.sol';
import { PriceMath } from './PriceMath.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

enum LimitOrderType {
    NONE,
    LOWER_LIMIT,
    UPPER_LIMIT
}

library LiquidityPosition {
    using PriceMath for uint160;
    using SignedFullMath for int256;
    using FullMath for uint256;
    using SafeCast for uint256;
    using LiquidityPosition for Info;
    using VTokenLib for VTokenAddress;
    using SignedFullMath for int256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    error AlreadyInitialized();
    error IneligibleLimitOrderRemoval();

    struct Info {
        //Extra boolean to check if it is limit order and uint to track limit price.
        LimitOrderType limitOrderType;
        // the tick range of the position; TODO Is storing ticks needed as it's in the positionId?
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        int256 vTokenAmountIn;
        // funding payment checkpoints
        int256 sumALastX128;
        int256 sumBInsideLastX128;
        int256 sumFpInsideLastX128;
        // fee growth inside
        uint256 sumFeeInsideLastX128;
        uint256[100] emptySlots; // reserved for adding variables when upgrading logic
    }

    function isInitialized(Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    function checkValidLimitOrderRemoval(Info storage info, int24 currentTick) internal view {
        if (
            !((currentTick >= info.tickUpper && info.limitOrderType == LimitOrderType.UPPER_LIMIT) ||
                (currentTick <= info.tickLower && info.limitOrderType == LimitOrderType.LOWER_LIMIT))
        ) {
            revert IneligibleLimitOrderRemoval();
        }
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
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int128 liquidity,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        position.update(accountNo, vTokenAddress, wrapper, balanceAdjustments);

        (int256 basePrincipal, int256 vTokenPrincipal) = wrapper.liquidityChange(
            position.tickLower,
            position.tickUpper,
            liquidity
        );
        balanceAdjustments.vBaseIncrease -= basePrincipal;
        balanceAdjustments.vTokenIncrease -= vTokenPrincipal;

        emit Account.LiquidityChange(
            accountNo,
            vTokenAddress,
            position.tickLower,
            position.tickUpper,
            liquidity,
            position.limitOrderType,
            -vTokenPrincipal,
            -basePrincipal
        );

        uint160 sqrtPriceCurrent = wrapper.vPool().sqrtPriceCurrent();
        {
            (int256 tokenAmountCurrent, ) = position.tokenAmountsInRange(sqrtPriceCurrent);

            balanceAdjustments.traderPositionIncrease += tokenAmountCurrent - position.vTokenAmountIn;
        }

        if (liquidity > 0) {
            position.liquidity += uint128(liquidity);
        } else if (liquidity < 0) {
            position.liquidity -= uint128(liquidity * -1);
        }

        (position.vTokenAmountIn, ) = position.tokenAmountsInRange(sqrtPriceCurrent);
    }

    function update(
        Info storage position,
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper, // TODO use vTokenLib
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        (int256 sumAX128, int256 sumBInsideX128, int256 sumFpInsideX128, uint256 sumFeeInsideX128) = wrapper
            .getValuesInside(position.tickLower, position.tickUpper);

        int256 fundingPayment = position.unrealizedFundingPayment(sumAX128, sumFpInsideX128);
        balanceAdjustments.vBaseIncrease += fundingPayment;

        int256 unrealizedLiquidityFee = position.unrealizedFees(sumFeeInsideX128).toInt256();
        balanceAdjustments.vBaseIncrease += unrealizedLiquidityFee;

        emit Account.FundingPayment(accountNo, vTokenAddress, position.tickLower, position.tickUpper, fundingPayment);
        emit Account.LiquidityFee(
            accountNo,
            vTokenAddress,
            position.tickLower,
            position.tickUpper,
            unrealizedLiquidityFee
        );
        // updating checkpoints
        position.sumALastX128 = sumAX128;
        position.sumBInsideLastX128 = sumBInsideX128;
        position.sumFpInsideLastX128 = sumFpInsideX128;
        position.sumFeeInsideLastX128 = sumFeeInsideX128;
    }

    function netPosition(Info storage position, IVPoolWrapper wrapper) internal view returns (int256) {
        (, int256 sumBInsideX128, , ) = wrapper.getValuesInside(position.tickLower, position.tickUpper);
        return position.netPosition(sumBInsideX128);
    }

    function netPosition(Info storage position, int256 sumBInsideX128) internal view returns (int256) {
        return (sumBInsideX128 - position.sumBInsideLastX128).mulDiv(position.liquidity, FixedPoint128.Q128);
    }

    function unrealizedFundingPayment(
        Info storage position,
        int256 sumAX128,
        int256 sumFpInsideX128
    ) internal view returns (int256 vBaseIncrease) {
        vBaseIncrease = (sumFpInsideX128 -
            (position.sumFpInsideLastX128 +
                position.sumBInsideLastX128.mulDiv(sumAX128 - position.sumALastX128, int256(FixedPoint128.Q128))))
            .mulDiv(position.liquidity, FixedPoint128.Q128);
    }

    function unrealizedFees(Info storage position, uint256 sumFeeInsideX128)
        internal
        view
        returns (uint256 vBaseIncrease)
    {
        vBaseIncrease = (sumFeeInsideX128 - position.sumFeeInsideLastX128).mulDiv(
            position.liquidity,
            FixedPoint128.Q128
        );
    }

    function maxNetPosition(
        Info storage position,
        VTokenAddress vToken,
        Constants memory constants
    ) internal view returns (uint256) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        return SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true);
    }

    function baseValue(
        Info storage position,
        uint160 sqrtPriceCurrent,
        VTokenAddress vToken,
        Constants memory constants
    ) internal view returns (int256 baseValue_) {
        return position.baseValue(sqrtPriceCurrent, vToken, vToken.vPoolWrapper(constants), constants);
    }

    function tokenAmountsInRange(Info storage position, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 vTokenAmount, int256 vBaseAmount)
    {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        // If price is outside the range, then consider it at the ends
        // for calculation of amounts
        uint160 sqrtPriceMiddleX96 = sqrtPriceCurrent;
        if (sqrtPriceCurrent < sqrtPriceLowerX96) {
            sqrtPriceMiddleX96 = sqrtPriceLowerX96;
        } else if (sqrtPriceCurrent > sqrtPriceUpperX96) {
            sqrtPriceMiddleX96 = sqrtPriceUpperX96;
        }

        vTokenAmount = SqrtPriceMath
            .getAmount0Delta(sqrtPriceMiddleX96, sqrtPriceUpperX96, position.liquidity, false)
            .toInt256();
        vBaseAmount = SqrtPriceMath
            .getAmount1Delta(sqrtPriceLowerX96, sqrtPriceMiddleX96, position.liquidity, false)
            .toInt256();
    }

    function baseValue(
        Info storage position,
        uint160 sqrtPriceCurrent,
        VTokenAddress vToken,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal view returns (int256 baseValue_) {
        {
            (int256 vTokenAmount, int256 vBaseAmount) = position.tokenAmountsInRange(sqrtPriceCurrent);
            uint256 priceX128 = sqrtPriceCurrent.toPriceX128();
            baseValue_ = vTokenAmount.mulDiv(priceX128, FixedPoint128.Q128) + vBaseAmount;
        }
        // adding fees
        (int256 sumAX128, , int256 sumFpInsideX128, uint256 sumFeeInsideX128) = wrapper.getValuesInside(
            position.tickLower,
            position.tickUpper
        );
        baseValue_ += position.unrealizedFees(sumFeeInsideX128).toInt256();
        baseValue_ += position.unrealizedFundingPayment(sumAX128, sumFpInsideX128);
    }
}
