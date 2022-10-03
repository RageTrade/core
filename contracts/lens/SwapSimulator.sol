// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { Simulate as SimulateUniswap } from '@uniswap/v3-core-0.8-support/contracts/libraries/Simulate.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { ClearingHouseExtsload } from '../extsloads/ClearingHouseExtsload.sol';
import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { SwapMath } from '../libraries/SwapMath.sol';
import { UniswapV3PoolHelper } from '../libraries/UniswapV3PoolHelper.sol';

contract SwapSimulator {
    using ClearingHouseExtsload for IClearingHouse;
    using SimulateSwap for IUniswapV3Pool;

    struct SwapStepAndState {
        SimulateSwap.Step step;
        SimulateSwap.State state;
    }

    SwapStepAndState[] _steps;

    /// @notice Simulate Swap with detailed tick cross info
    /// @dev These parameters are similar to ClearingHouse's swapToken function
    /// @param clearingHouse The ClearingHouse address
    /// @param poolId The poolId of the pool to be simulated on
    /// @param amount The amount of token to be swapped, positive for long, negative for short
    /// @param sqrtPriceLimitX96 The slippage limit of the swap, use zero for unbounded slippage
    /// @param isNotional Whether the amount is in vQuote/dollar terms, use false for vToken
    function simulateSwap(
        IClearingHouse clearingHouse,
        uint32 poolId,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    )
        public
        returns (
            IVPoolWrapper.SwapResult memory swapResult,
            SimulateSwap.Cache memory cache,
            SwapStepAndState[] memory steps
        )
    {
        IClearingHouseStructures.Pool memory poolInfo = clearingHouse.getPoolInfo(poolId);

        return
            simulateSwapOnVPool(
                poolInfo.vPool,
                poolInfo.vPoolWrapper.liquidityFeePips(),
                poolInfo.vPoolWrapper.protocolFeePips(),
                amount < 0,
                isNotional ? amount : -amount,
                sqrtPriceLimitX96
            );
    }

    /// @notice Simulate Swap with detailed tick cross info
    /// @dev These parameters are similar to IUniswapV3Pool's swap function
    /// @param vPool The vPool address
    /// @param liquidityFeePips The liquidity fee pips, available from poolInfo in clearingHouse
    /// @param protocolFeePips The protocol fee pips, available from poolInfo in clearingHouse
    /// @param swapVTokenForVQuote Whether vToken is being sold or shorted
    /// @param amountSpecified Amount to be swapped, positive for exactIn and negative for exactOut
    /// @param sqrtPriceLimitX96 The slippage limit of the swap, use zero for unbounded slippage
    function simulateSwapOnVPool(
        IUniswapV3Pool vPool,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        public
        returns (
            IVPoolWrapper.SwapResult memory swapResult,
            SimulateSwap.Cache memory cache,
            SwapStepAndState[] memory steps
        )
    {
        delete _steps;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        swapResult.amountSpecified = amountSpecified;
        bool exactIn = amountSpecified >= 0;
        uint24 uniswapFeePips = vPool.fee();

        SwapMath.beforeSwap(
            exactIn,
            swapVTokenForVQuote,
            uniswapFeePips,
            liquidityFeePips,
            protocolFeePips,
            swapResult
        );

        // simulate swap and record tick crosses
        SimulateSwap.State memory state;
        (swapResult.vTokenIn, swapResult.vQuoteIn, state, cache) = vPool.simulateSwap(
            swapVTokenForVQuote,
            swapResult.amountSpecified,
            sqrtPriceLimitX96,
            _onSwapStep
        );

        SwapMath.afterSwap(exactIn, swapVTokenForVQuote, uniswapFeePips, liquidityFeePips, protocolFeePips, swapResult);

        swapResult.sqrtPriceX96Start = cache.sqrtPriceX96Start;
        swapResult.sqrtPriceX96End = state.sqrtPriceX96;

        steps = _steps;
    }

    /// @notice Simulate Swap in a cheap way, by ignoring any tick cross details
    /// @dev These parameters are similar to ClearingHouse's swapToken function
    /// @param clearingHouse The ClearingHouse address
    /// @param poolId The poolId of the pool to be simulated on
    /// @param amount The amount of token to be swapped, positive for long, negative for short
    /// @param sqrtPriceLimitX96 The slippage limit of the swap, use zero for unbounded slippage
    /// @param isNotional Whether the amount is in vQuote/dollar terms, use false for vToken
    function simulateSwapView(
        IClearingHouse clearingHouse,
        uint32 poolId,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    ) public view returns (IVPoolWrapper.SwapResult memory swapResult) {
        IClearingHouseStructures.Pool memory poolInfo = clearingHouse.getPoolInfo(poolId);

        swapResult = simulateSwapOnVPoolView(
            poolInfo.vPool,
            poolInfo.vPoolWrapper.liquidityFeePips(),
            poolInfo.vPoolWrapper.protocolFeePips(),
            amount < 0,
            isNotional ? amount : -amount,
            sqrtPriceLimitX96
        );
    }

    /// @notice Simulate Swap in a cheap way, by ignoring any tick cross details
    /// @dev These parameters are similar to IUniswapV3Pool's swap function
    /// @param vPool The vPool address
    /// @param liquidityFeePips The liquidity fee pips, available from poolInfo in clearingHouse
    /// @param protocolFeePips The protocol fee pips, available from poolInfo in clearingHouse
    /// @param swapVTokenForVQuote Whether vToken is being sold or shorted
    /// @param amountSpecified Amount to be swapped, positive for exactIn and negative for exactOut
    /// @param sqrtPriceLimitX96 The slippage limit of the swap, use zero for unbounded slippage
    function simulateSwapOnVPoolView(
        IUniswapV3Pool vPool,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public view returns (IVPoolWrapper.SwapResult memory swapResult) {
        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        swapResult.amountSpecified = amountSpecified;
        bool exactIn = amountSpecified >= 0;
        uint24 uniswapFeePips = vPool.fee();

        SwapMath.beforeSwap(
            exactIn,
            swapVTokenForVQuote,
            uniswapFeePips,
            liquidityFeePips,
            protocolFeePips,
            swapResult
        );

        // simulate swap and ignore tick crosses
        (swapResult.vTokenIn, swapResult.vQuoteIn) = SimulateUniswap.simulateSwap(
            vPool,
            swapVTokenForVQuote,
            swapResult.amountSpecified,
            sqrtPriceLimitX96
        );

        SwapMath.afterSwap(exactIn, swapVTokenForVQuote, uniswapFeePips, liquidityFeePips, protocolFeePips, swapResult);
    }

    function _onSwapStep(
        bool,
        SimulateSwap.Cache memory,
        SimulateSwap.State memory state,
        SimulateSwap.Step memory step
    ) internal {
        // for reading
        _steps.push(SwapStepAndState({ state: state, step: step }));
    }
}
