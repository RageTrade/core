//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import { FundingPayment } from '../libraries/FundingPayment.sol';
import { SimulateSwap } from '../libraries/SimulateSwap.sol';
import { Tick } from '../libraries/Tick.sol';

import { IOracle } from '../interfaces/IOracle.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { console } from 'hardhat/console.sol';

contract SimulateSwapTest is IUniswapV3SwapCallback {
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SafeERC20 for IERC20;
    using SimulateSwap for IUniswapV3Pool;
    using Tick for mapping(int24 => Tick.Info);

    IUniswapV3Pool vPool;

    struct SwapStep {
        SimulateSwap.SwapState state;
        SimulateSwap.StepComputations step;
    }
    SimulateSwap.SwapCache _cache;
    SwapStep[] _steps;

    FundingPayment.Info public fpGlobal;
    uint256 public extendedFeeGrowthOutsideX128;
    mapping(int24 => Tick.Info) public ticksExtended;

    constructor(IUniswapV3Pool vPool_) {
        vPool = vPool_;
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

    function simulateSwap3(
        bool swapVTokenForVQuote,
        int256 amountSpecified,
        uint24 fee
    ) public returns (int256 vTokenIn, int256 vQuoteIn) {
        // case isNotional true
        // amountSpecified is positive
        return
            vPool.simulateSwap(
                swapVTokenForVQuote,
                amountSpecified,
                swapVTokenForVQuote ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                fee,
                _onSwapSwap
            );
    }

    function _onSwapSwap(
        bool,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        // for reading
        _cache = cache;
        _steps.push(SwapStep({ state: state, step: step }));
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
            IERC20(vPool.token0()).safeTransferFrom(receipient, address(vPool), uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IERC20(vPool.token1()).safeTransferFrom(receipient, address(vPool), uint256(amount1Delta));
        }
    }
}
