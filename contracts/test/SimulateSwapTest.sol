//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FundingPayment } from '../libraries/FundingPayment.sol';
import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { Tick } from '../libraries/Tick.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IOracle } from '../interfaces/IOracle.sol';

import { console } from 'hardhat/console.sol';

contract SimulateSwapTest is IUniswapV3SwapCallback {
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SimulateSwap for IUniswapV3Pool;
    using Tick for mapping(int24 => Tick.Info);
    using VTokenLib for VTokenAddress;

    IUniswapV3Pool vPool;
    IOracle oracle;

    bool public isToken0;

    struct SwapStep {
        SimulateSwap.SwapState state;
        SimulateSwap.StepComputations step;
    }
    SimulateSwap.SwapCache _cache;
    SwapStep[] _steps;

    FundingPayment.Info public fpGlobal;
    uint256 public extendedFeeGrowthOutsideX128;
    mapping(int24 => Tick.Info) public extendedTicks;

    constructor(IUniswapV3Pool vPool_, IOracle oracle_) {
        vPool = vPool_;
        oracle = oracle_;
    }

    function setIsToken0(bool isToken0_) external {
        isToken0 = isToken0_;
    }

    function clearSwapCache() external {
        delete _cache;
        delete _steps;
    }

    function sqrtPrice() external view returns (uint160 sq) {
        (sq, , , , , , ) = vPool.slot0();
    }

    function simulateSwap1(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 amount0, int256 amount1) {
        return vPool.simulateSwap(zeroForOne, amountSpecified, sqrtPriceLimitX96, _onSwapSwap);
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

    function _onSwapSwap(
        bool zeroForOne,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        // for reading
        _cache = cache;
        _steps.push(SwapStep({ state: state, step: step }));

        fpGlobal.update(
            zeroForOne == isToken0 ? int256(step.amountIn) : int256(step.amountOut),
            state.liquidity,
            cache.blockTimestamp,
            oracle.getTwapSqrtPriceX96(1 hours),
            (isToken0 ? step.amountIn : step.amountOut).mulDiv(
                FixedPoint128.Q128,
                isToken0 ? step.amountOut : step.amountIn
            )
        );

        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                extendedTicks.cross(step.tickNext, fpGlobal, extendedFeeGrowthOutsideX128);
            }
        }
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
