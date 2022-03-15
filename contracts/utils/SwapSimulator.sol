// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { SwapMath } from '../libraries/SwapMath.sol';
import { UniswapV3PoolHelper } from '../libraries/UniswapV3PoolHelper.sol';

contract SwapSimulator {
    using SimulateSwap for IUniswapV3Pool;

    struct SwapStepAndState {
        SimulateSwap.Step step;
        SimulateSwap.State state;
    }

    SimulateSwap.Cache _cache;
    SwapStepAndState[] _steps;
    uint160 _sqrtPriceX96End;

    function simulateSwap(
        IClearingHouse clearingHouse,
        uint32 poolId,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    )
        public
        returns (
            IClearingHouseStructures.SwapValues memory swapValues,
            uint160 sqrtPriceX96End,
            SimulateSwap.Cache memory cache,
            SwapStepAndState[] memory steps
        )
    {
        IClearingHouseStructures.Pool memory poolInfo = clearingHouse.getPoolInfo(poolId);

        swapValues = _simulateSwap(
            poolInfo.vPool,
            poolInfo.vPoolWrapper.liquidityFeePips(),
            poolInfo.vPoolWrapper.protocolFeePips(),
            amount < 0,
            isNotional ? amount : -amount,
            sqrtPriceLimitX96,
            _onSwapStep
        );
        sqrtPriceX96End = _sqrtPriceX96End;
        cache = _cache;
        steps = _steps;
    }

    function _simulateSwap(
        IUniswapV3Pool vPool,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        function(bool, SimulateSwap.Cache memory, SimulateSwap.State memory, SimulateSwap.Step memory) onSwapStep
    ) internal returns (IClearingHouseStructures.SwapValues memory swapValues) {
        delete _cache;
        delete _steps;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        swapValues.amountSpecified = amountSpecified;
        bool exactIn = amountSpecified >= 0;
        uint24 uniswapFeePips = vPool.fee();

        SwapMath.beforeSwap(
            exactIn,
            swapVTokenForVQuote,
            uniswapFeePips,
            liquidityFeePips,
            protocolFeePips,
            swapValues
        );

        // simulate swap and update our tick states
        (swapValues.vTokenIn, swapValues.vQuoteIn) = vPool.simulateSwap(
            swapVTokenForVQuote,
            amountSpecified,
            sqrtPriceLimitX96,
            onSwapStep
        );

        SwapMath.afterSwap(exactIn, swapVTokenForVQuote, uniswapFeePips, liquidityFeePips, protocolFeePips, swapValues);
    }

    function _onSwapStep(
        bool,
        SimulateSwap.Cache memory cache,
        SimulateSwap.State memory state,
        SimulateSwap.Step memory step
    ) internal {
        // for reading
        _cache = cache;
        _steps.push(SwapStepAndState({ state: state, step: step }));
        _sqrtPriceX96End = state.sqrtPriceX96;
    }
}
