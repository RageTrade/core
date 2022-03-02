//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SqrtPriceMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/SqrtPriceMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { Account } from './Account.sol';
import { PriceMath } from './PriceMath.sol';
import { Protocol } from './Protocol.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { FundingPayment } from './FundingPayment.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPosition {
    using PriceMath for uint160;
    using SignedFullMath for int256;
    using FullMath for uint256;
    using SafeCast for uint256;
    using LiquidityPosition for Info;
    using Protocol for Protocol.Info;
    using SignedFullMath for int256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    struct Info {
        //Extra boolean to check if it is limit order and uint to track limit price.
        IClearingHouseEnums.LimitOrderType limitOrderType;
        // the tick range of the position;
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
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error AlreadyInitialized();
    error IneligibleLimitOrderRemoval();

    function isInitialized(Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    function checkValidLimitOrderRemoval(Info storage info, int24 currentTick) internal view {
        if (
            !((currentTick >= info.tickUpper &&
                info.limitOrderType == IClearingHouseEnums.LimitOrderType.UPPER_LIMIT) ||
                (currentTick <= info.tickLower &&
                    info.limitOrderType == IClearingHouseEnums.LimitOrderType.LOWER_LIMIT))
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
        uint256 accountId,
        uint32 poolId,
        int128 liquidity,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        (
            int256 basePrincipal,
            int256 vTokenPrincipal,
            IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside
        ) = wrapper.liquidityChange(position.tickLower, position.tickUpper, liquidity);

        position.update(accountId, poolId, wrapperValuesInside, balanceAdjustments);

        balanceAdjustments.vBaseIncrease -= basePrincipal;
        balanceAdjustments.vTokenIncrease -= vTokenPrincipal;

        emit Account.LiquidityChange(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            liquidity,
            position.limitOrderType,
            -vTokenPrincipal,
            -basePrincipal
        );

        uint160 sqrtPriceCurrent = wrapper.vPool().sqrtPriceCurrent(); // TODO change to poolId.vPool()
        int256 tokenAmountCurrent;
        {
            (tokenAmountCurrent, ) = position.tokenAmountsInRange(sqrtPriceCurrent, false);
            balanceAdjustments.traderPositionIncrease += (tokenAmountCurrent - position.vTokenAmountIn);
        }

        if (liquidity > 0) {
            position.liquidity += uint128(liquidity);
        } else if (liquidity < 0) {
            position.liquidity -= uint128(liquidity * -1);
        }

        position.vTokenAmountIn = tokenAmountCurrent + vTokenPrincipal;
    }

    function update(
        Info storage position,
        uint256 accountId,
        uint32 poolId,
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        int256 fundingPayment = position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
        balanceAdjustments.vBaseIncrease += fundingPayment;

        int256 unrealizedLiquidityFee = position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        balanceAdjustments.vBaseIncrease += unrealizedLiquidityFee;

        emit Account.FundingPayment(accountId, poolId, position.tickLower, position.tickUpper, fundingPayment);
        emit Account.LiquidityFee(accountId, poolId, position.tickLower, position.tickUpper, unrealizedLiquidityFee);
        // updating checkpoints
        position.sumALastX128 = wrapperValuesInside.sumAX128;
        position.sumBInsideLastX128 = wrapperValuesInside.sumBInsideX128;
        position.sumFpInsideLastX128 = wrapperValuesInside.sumFpInsideX128;
        position.sumFeeInsideLastX128 = wrapperValuesInside.sumFeeInsideX128;
    }

    function netPosition(Info storage position, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 netTokenPosition)
    {
        int256 tokenAmountCurrent;
        (tokenAmountCurrent, ) = position.tokenAmountsInRange(sqrtPriceCurrent, false);
        netTokenPosition = (tokenAmountCurrent - position.vTokenAmountIn);
    }

    // use funding payment lib
    function unrealizedFundingPayment(
        Info storage position,
        int256 sumAX128,
        int256 sumFpInsideX128
    ) internal view returns (int256 vBaseIncrease) {
        vBaseIncrease = -FundingPayment.bill(
            sumAX128,
            sumFpInsideX128,
            position.sumALastX128,
            position.sumBInsideLastX128,
            position.sumFpInsideLastX128,
            position.liquidity
        );
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

    function maxNetPosition(Info storage position) internal view returns (uint256) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        if (position.vTokenAmountIn >= 0)
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) -
                uint256(position.vTokenAmountIn);
        else
            return
                SqrtPriceMath.getAmount0Delta(sqrtPriceLowerX96, sqrtPriceUpperX96, position.liquidity, true) +
                uint256(-1 * position.vTokenAmountIn);
    }

    function longSideRisk(
        Info storage position,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (uint256) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);
        uint256 longPositionExecutionPriceX96;
        {
            uint160 sqrtPriceTwapX96 = protocol.getVirtualTwapSqrtPriceX96For(poolId);
            uint160 sqrtPriceForExecutionPriceX96 = sqrtPriceTwapX96 <= sqrtPriceUpperX96
                ? sqrtPriceTwapX96
                : sqrtPriceUpperX96;
            longPositionExecutionPriceX96 = uint256(sqrtPriceLowerX96).mulDiv(
                sqrtPriceForExecutionPriceX96,
                FixedPoint96.Q96
            );
        }

        uint256 maxNetLongPosition;
        {
            uint256 maxLongTokens = SqrtPriceMath.getAmount0Delta(
                sqrtPriceLowerX96,
                sqrtPriceUpperX96,
                position.liquidity,
                true
            );
            //
            if (position.vTokenAmountIn >= 0) {
                //maxLongTokens in range should always be >= amount that got added to range, equality occurs when range was added at pCurrent = pHigh
                assert(maxLongTokens >= uint256(position.vTokenAmountIn));
                maxNetLongPosition = maxLongTokens - uint256(position.vTokenAmountIn);
            } else maxNetLongPosition = maxLongTokens + uint256(-1 * position.vTokenAmountIn);
        }

        return maxNetLongPosition.mulDiv(longPositionExecutionPriceX96, FixedPoint96.Q96);
    }

    function marketValue(
        Info storage position,
        uint160 valuationSqrtPriceX96,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256 marketValue_) {
        return position.marketValue(valuationSqrtPriceX96, protocol.vPoolWrapperFor(poolId));
    }

    function tokenAmountsInRange(
        Info storage position,
        uint160 sqrtPriceCurrent,
        bool roundUp
    ) internal view returns (int256 vTokenAmount, int256 vBaseAmount) {
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
            .getAmount0Delta(sqrtPriceMiddleX96, sqrtPriceUpperX96, position.liquidity, roundUp)
            .toInt256();
        vBaseAmount = SqrtPriceMath
            .getAmount1Delta(sqrtPriceLowerX96, sqrtPriceMiddleX96, position.liquidity, roundUp)
            .toInt256();
    }

    function marketValue(
        Info storage position,
        uint160 valuationSqrtPriceX96,
        IVPoolWrapper wrapper
    ) internal view returns (int256 marketValue_) {
        {
            (int256 vTokenAmount, int256 vBaseAmount) = position.tokenAmountsInRange(valuationSqrtPriceX96, false);
            uint256 priceX128 = valuationSqrtPriceX96.toPriceX128();
            marketValue_ = vTokenAmount.mulDiv(priceX128, FixedPoint128.Q128) + vBaseAmount;
        }
        // adding fees
        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = wrapper.getExtrapolatedValuesInside(
            position.tickLower,
            position.tickUpper
        );
        marketValue_ += position.unrealizedFees(wrapperValuesInside.sumFeeInsideX128).toInt256();
        marketValue_ += position.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );
    }
}
