//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SimulateSwap } from '../libraries/SimulateSwap.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { console } from 'hardhat/console.sol';

contract SimulateSwapTest is IUniswapV3SwapCallback {
    using SimulateSwap for IUniswapV3Pool;

    IUniswapV3Pool vPool;

    constructor(IUniswapV3Pool vPool_) {
        vPool = vPool_;
    }

    function simulateSwap1(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 amount0, int256 amount1) {
        return vPool.simulateSwap(zeroForOne, amountSpecified, sqrtPriceLimitX96);
    }

    function sqrtPrice() external view returns (uint160 sq) {
        (sq, , , , , , ) = vPool.slot0();
    }

    function simulateSwap2(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        public
        returns (
            int256 amount0,
            int256 amount1,
            SimulateSwap.SwapCache memory cache,
            SwapStep[] memory steps
        )
    {
        (amount0, amount1) = vPool.simulateSwap(zeroForOne, amountSpecified, sqrtPriceLimitX96, _onSwapSwap);
        cache = _cache;
        steps = _steps;
    }

    struct SwapStep {
        SimulateSwap.SwapState state;
        SimulateSwap.StepComputations step;
    }
    SimulateSwap.SwapCache _cache;
    SwapStep[] _steps;

    function _onSwapSwap(
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        _cache = cache;
        _steps.push(SwapStep({ state: state, step: step }));
        console.log('SwapStep');
        console.log('amountIn', step.amountIn);
        console.log('amountOut', step.amountOut);
        console.log('liquidity', state.liquidity);
        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                console.log('is initialized');
            }
        }
        console.log('');
    }

    function swap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1) {
        return vPool.swap(msg.sender, zeroForOne, amountSpecified, sqrtPriceLimitX96, abi.encode(msg.sender));
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(msg.sender == address(vPool));
        address receipient = abi.decode(data, (address));
        if (amount0Delta > 0) {
            IERC20(vPool.token0()).transferFrom(receipient, address(vPool), uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(vPool.token1()).transferFrom(receipient, address(vPool), uint256(amount1Delta));
        }
    }
}
