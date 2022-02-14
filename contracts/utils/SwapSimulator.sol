//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { SwapMath } from '../libraries/SwapMath.sol';
import { UniswapV3PoolHelper } from '../libraries/UniswapV3PoolHelper.sol';

contract SwapSimulator {
    using SimulateSwap for IUniswapV3Pool;

    struct SwapStep {
        SimulateSwap.SwapState state;
        SimulateSwap.StepComputations step;
    }

    function simulateSwap(
        IClearingHouse clearingHouse,
        IVToken vToken,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    ) external returns (IClearingHouse.SwapValues memory swapValues) {
        // case isNotional true
        // amountSpecified is positive
        return
            _simulateSwap(
                clearingHouse,
                vToken,
                amount < 0,
                isNotional ? amount : -amount,
                sqrtPriceLimitX96,
                _emptyFunction
            );
    }

    function simulateSwapWithTickData(
        IClearingHouse clearingHouse,
        IVToken vToken,
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    )
        external
        returns (
            IClearingHouse.SwapValues memory swapValues,
            SimulateSwap.SwapCache memory cache,
            SwapStep[] memory steps
        )
    {
        // case isNotional true
        // amountSpecified is positive
        swapValues = _simulateSwap(
            clearingHouse,
            vToken,
            amount < 0,
            isNotional ? amount : -amount,
            sqrtPriceLimitX96,
            _recordStep
        );

        cache = _cache;
        steps = _steps;
        delete _cache;
        delete _steps;
    }

    SimulateSwap.SwapCache _cache;
    SwapStep[] _steps;

    function _recordStep(
        bool,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        // for reading
        _cache = cache;
        _steps.push(SwapStep({ state: state, step: step }));
    }

    function _emptyFunction(
        bool,
        SimulateSwap.SwapCache memory,
        SimulateSwap.SwapState memory,
        SimulateSwap.StepComputations memory
    ) internal {}

    function _simulateSwap(
        IClearingHouse clearingHouse,
        IVToken vToken,
        bool swapVTokenForVBase, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        function(
            bool,
            SimulateSwap.SwapCache memory,
            SimulateSwap.SwapState memory,
            SimulateSwap.StepComputations memory
        ) onSwapStep
    ) internal returns (IClearingHouse.SwapValues memory swapValues) {
        swapValues.amountSpecified = amountSpecified;

        IClearingHouse.RageTradePool memory pool = clearingHouse.pools(vToken);

        bool exactIn = amountSpecified >= 0;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVBase ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        (uint24 uniswapFeePips, uint24 liquidityFeePips, uint24 protocolFeePips) = (
            pool.vPool.fee(),
            pool.vPoolWrapper.liquidityFeePips(),
            pool.vPoolWrapper.protocolFeePips()
        );

        SwapMath.beforeSwap(exactIn, swapVTokenForVBase, uniswapFeePips, liquidityFeePips, protocolFeePips, swapValues);

        {
            // simulate swap and update our tick states
            (int256 vTokenIn_simulated, int256 vBaseIn_simulated) = pool.vPool.simulateSwap(
                swapVTokenForVBase,
                amountSpecified,
                sqrtPriceLimitX96,
                onSwapStep
            );

            // execute actual swap on uniswap
            (swapValues.vTokenIn, swapValues.vBaseIn) = pool.vPool.swap(
                address(this),
                swapVTokenForVBase,
                amountSpecified,
                sqrtPriceLimitX96,
                ''
            );

            // simulated swap should be identical to actual swap
            assert(vTokenIn_simulated == swapValues.vTokenIn && vBaseIn_simulated == swapValues.vBaseIn);
        }

        SwapMath.afterSwap(exactIn, swapVTokenForVBase, uniswapFeePips, liquidityFeePips, protocolFeePips, swapValues);
    }
}
