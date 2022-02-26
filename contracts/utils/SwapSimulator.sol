//SPDX-License-Identifier: UNLICENSED

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
    )
        external
        returns (
            IClearingHouseStructures.SwapValues memory swapValues,
            uint160 sqrtPriceX96End,
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
            _onSwapStep
        );

        cache = _cache;
        steps = _steps;
        sqrtPriceX96End = _sqrtPriceX96End;
        delete _cache;
        delete _steps;
        delete _sqrtPriceX96End;
    }

    SimulateSwap.SwapCache _cache;
    SwapStep[] _steps;
    uint160 _sqrtPriceX96End;

    function _onSwapStep(
        bool,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        // for reading
        _cache = cache;
        _steps.push(SwapStep({ state: state, step: step }));
        _sqrtPriceX96End = state.sqrtPriceX96;
    }

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
    ) internal returns (IClearingHouseStructures.SwapValues memory swapValues) {
        swapValues.amountSpecified = amountSpecified;

        IClearingHouseStructures.Pool memory pool = clearingHouse.pools(vToken);

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
            (swapValues.vTokenIn, swapValues.vBaseIn) = pool.vPool.simulateSwap(
                swapVTokenForVBase,
                amountSpecified,
                sqrtPriceLimitX96,
                onSwapStep
            );
        }

        SwapMath.afterSwap(exactIn, swapVTokenForVBase, uniswapFeePips, liquidityFeePips, protocolFeePips, swapValues);
    }
}
