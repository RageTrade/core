//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolWrapperDeployer.sol';
import { VTokenAddress, VTokenLib, IUniswapV3Pool, Constants } from './libraries/VTokenLib.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/IVBase.sol';
import './interfaces/IVToken.sol';
import { IOracle } from './interfaces/IOracle.sol';
import { IVToken } from './interfaces/IVToken.sol';
import { IUniswapV3PoolDeployer } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3PoolDeployer.sol';

import { FixedPoint128 } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FundingPayment } from './libraries/FundingPayment.sol';
import { SimulateSwap } from './libraries/SimulateSwap.sol';
import { Tick } from './libraries/Tick.sol';
import { TickMath } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { PriceMath } from './libraries/PriceMath.sol';
import { SignedMath } from './libraries/SignedMath.sol';
import { SignedFullMath } from './libraries/SignedFullMath.sol';
import { UniswapV3PoolHelper } from './libraries/UniswapV3PoolHelper.sol';

import { Oracle } from './libraries/Oracle.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SignedMath for int256;
    using SignedFullMath for int256;

    using PriceMath for uint160;
    using SafeCast for uint256;
    using Oracle for IUniswapV3Pool;
    using SimulateSwap for IUniswapV3Pool;
    using Tick for IUniswapV3Pool;
    using Tick for mapping(int24 => Tick.Info);
    using UniswapV3PoolHelper for IUniswapV3Pool;
    using VTokenLib for VTokenAddress;

    uint16 public immutable initialMarginRatio;
    uint16 public immutable maintainanceMarginRatio;
    uint32 public immutable timeHorizon;
    VTokenAddress public immutable vToken;
    IUniswapV3Pool public immutable vPool;

    // fee collected by Uniswap
    uint24 public immutable uniswapFeePips;

    // fee paid to liquidity providers, in 1e6
    uint24 public liquidityFeePips;

    // fee paid to DAO
    uint24 public protocolFeePips;

    uint256 public accruedProtocolFee;

    bool public whitelisted;

    // oracle for real prices
    IOracle public oracle;

    FundingPayment.Info public fpGlobal;
    uint256 public sumFeeGlobalX128; // extendedFeeGrowthGlobalX128;
    mapping(int24 => Tick.Info) public ticksExtended;

    Constants public constants;

    constructor() {
        address vTokenAddress;
        address vPoolAddress;
        (
            vTokenAddress,
            vPoolAddress,
            liquidityFeePips,
            protocolFeePips,
            initialMarginRatio,
            maintainanceMarginRatio,
            timeHorizon,
            whitelisted,
            constants
        ) = IVPoolWrapperDeployer(msg.sender).parameters();
        vToken = VTokenAddress.wrap(vTokenAddress);
        vPool = IUniswapV3Pool(vPoolAddress);
        uniswapFeePips = vPool.fee();
    }

    // TODO move this to ClearingHouse
    // TODO restrict this to governance
    function setOracle(address oracle_) external {
        oracle = IOracle(oracle_);
    }

    // TODO move this to ClearingHouse
    // TODO restrict this to governance
    function setWhitelisted(bool whitelisted_) external {
        whitelisted = whitelisted_;
    }

    // TODO restrict this to governance
    function setLiquidityFee(uint24 liquidityFeePips_) external {
        liquidityFeePips = liquidityFeePips_;
    }

    // TODO restrict this to governance
    function setProtocolFee(uint24 protocolFeePips_) external {
        protocolFeePips = protocolFeePips_;
    }

    function collectAccruedProtocolFee() external returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = accruedProtocolFee - 1;
        accruedProtocolFee = 1;
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int256 sumAX128,
            int256 sumBInsideX128,
            int256 sumFpInsideX128,
            uint256 sumFeeInsideX128
        )
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;
        sumAX128 = _fpGlobal.sumAX128;
        (sumBInsideX128, sumFpInsideX128, sumFeeInsideX128) = ticksExtended.getTickExtendedStateInside(
            tickLower,
            tickUpper,
            currentTick,
            _fpGlobal,
            sumFeeGlobalX128
        );
    }

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount) {
        (vBaseAmount, vTokenAmount) = swap(isNotional, amount, sqrtPriceLimit);
    }

    function _inflate(int256 amount) internal view returns (int256 inflated) {
        inflated = (amount * 1e6) / int24(1e6 - uniswapFeePips);
    }

    function _deinflate(uint256 inflated, bool roundUp) internal view returns (uint256 amount) {
        amount = (inflated * (1e6 - uniswapFeePips)) / 1e6;
        amount += 1;
    }

    function _deinflate(int256 inflated, bool roundUp) internal view returns (int256 amount) {
        amount = (inflated * int24(1e6 - uniswapFeePips)) / 1e6;
        amount += 1;
    }

    function _calculateFees(uint256 amount, bool add)
        internal
        view
        returns (
            uint256 amountAfterFees,
            uint256 liquidityFees,
            uint256 protocolFees
        )
    {
        int256 amountAfterFees_;
        (amountAfterFees_, liquidityFees, protocolFees) = _calculateFees(int256(amount), add);
        amountAfterFees = uint256(amountAfterFees_);
    }

    function _calculateFees(int256 amount, bool add)
        internal
        view
        returns (
            int256 amountAfterFees,
            uint256 liquidityFees,
            uint256 protocolFees
        )
    {
        uint256 amountAbs = uint256(amount.abs());
        liquidityFees = (amountAbs * liquidityFeePips) / 1e6;
        protocolFees = (amountAbs * protocolFeePips) / 1e6;
        if (add) {
            // TODO: this approximation works for small amounts, what will happen for larger amounts?
            // amountAfterFees = (amount * 1e6) / int256(uint256(1e6 - liquidityFeePips - protocolFeePips));
            amountAfterFees = amount + int256(liquidityFees + protocolFees);
        } else {
            amountAfterFees = amount - int256(liquidityFees + protocolFees);
        }
    }

    /// @notice swaps token
    /// @param amountSpecified: positive means long, negative means short
    /// @param isNotional: true means amountSpecified is dollar amount
    /// @param sqrtPriceLimitX96: The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap.
    function swap(
        bool isNotional,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 vBaseIn, int256 vTokenIn) {
        // case isNotional true
        // amountSpecified is positive
        return _swap(amountSpecified < 0, isNotional ? amountSpecified : -amountSpecified, sqrtPriceLimitX96);
    }

    /// @notice Swap vToken for vBase, or vBase for vToken
    /// @param swapVTokenForVBase: The direction of the swap, true for vToken to vBase, false for vBase to vToken
    /// @param amountSpecified: The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param sqrtPriceLimitX96: The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap.
    function _swap(
        bool swapVTokenForVBase, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal returns (int256 vBaseIn, int256 vTokenIn) {
        bool exactIn = amountSpecified >= 0;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVBase ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        uint256 liquidityFees;
        uint256 protocolFees;

        // if vBase amount specified, then process fee before swap
        if (swapVTokenForVBase == (amountSpecified < 0)) {
            if (exactIn) {
                // if exactIn VBase, remove fee and do smaller swap, so trader gets less vTokens
                (amountSpecified, liquidityFees, protocolFees) = _calculateFees(amountSpecified, false);
            } else {
                // if exactOut VBase, buy more (short more vToken) so that fee can be removed in vBase
                (amountSpecified, liquidityFees, protocolFees) = _calculateFees(amountSpecified, true);
            }
        }

        // for exactIn, uniswap fees are directly collected in uniswap pool
        if (exactIn) {
            // inflate amount so that fees collected in uniswap does not matter
            amountSpecified = _inflate(amountSpecified);
        }

        {
            // simulate swap and update our tick states
            (int256 vTokenIn_simulated, int256 vBaseIn_simulated, ) = vPool.simulateSwap(
                swapVTokenForVBase,
                amountSpecified,
                sqrtPriceLimitX96,
                _onSwapStep
            );

            // execute actual swap on uniswap
            (vTokenIn, vBaseIn) = vPool.swap(address(this), swapVTokenForVBase, amountSpecified, sqrtPriceLimitX96, '');

            // TODO should this check be removed in production?
            // simulated swap should be identical to actual swap
            assert(vTokenIn_simulated == vTokenIn && vBaseIn_simulated == vBaseIn);
        }

        // deinflate
        if (exactIn) {
            if (swapVTokenForVBase) {
                vTokenIn = _deinflate(vTokenIn, !swapVTokenForVBase);
            } else {
                vBaseIn = _deinflate(vBaseIn, !swapVTokenForVBase);
            }
        }

        // if vToken amount was specified, then process fee after swap
        if (swapVTokenForVBase == (amountSpecified >= 0)) {
            if (exactIn) {
                // if exactIn vToken, then give less vBaseOut to trader.
                assert(vBaseIn < 0);
                (vBaseIn, liquidityFees, protocolFees) = _calculateFees(vBaseIn, false);
            } else {
                // if exactOut vToken, increase vBaseIn, so that trader is charged more vBase
                assert(vBaseIn > 0);
                (vBaseIn, liquidityFees, protocolFees) = _calculateFees(vBaseIn, true);
            }
        }

        // charge the trader the removed protocol and liquidity fees to vbase so that trader takes the hit
        if (swapVTokenForVBase && amountSpecified < 0) {
            vBaseIn -= int256(protocolFees + liquidityFees);
        } else {
            vBaseIn += int256(protocolFees + liquidityFees);
        }

        // record the protocol fee, for withdrawal in future
        accruedProtocolFee += protocolFees;

        // burn the tokens received from the swap
        _vBurn();
    }

    function _onSwapStep(
        bool swapVTokenForVBase,
        SimulateSwap.SwapCache memory,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal returns (uint256 protocolFeeForThisStep) {
        // TODO remove protocolFeeForThisStep
        bool exactIn = state.amountCalculated < 0;

        // vBase and vToken amounts are inflated-deinflated to give effect of zero fee swap
        uint256 lpFeesInVBase;
        uint256 vTokenAmount;
        uint256 vBaseAmount;
        if (exactIn) {
            if (swapVTokenForVBase) {
                vTokenAmount = step.amountIn;
                (, lpFeesInVBase, ) = _calculateFees(vBaseAmount = step.amountOut, true); // TODO optimise/change this function
            } else {
                vTokenAmount = step.amountOut;
                (, lpFeesInVBase, ) = _calculateFees(vBaseAmount = step.amountIn, true); // TODO optimise/change this function
            }
        } else {
            if (swapVTokenForVBase) {
                vTokenAmount = _deinflate(step.amountIn, true);
                (, lpFeesInVBase, ) = _calculateFees(vBaseAmount = step.amountOut, true);
            } else {
                vTokenAmount = step.amountOut;
                (, lpFeesInVBase, ) = _calculateFees(vBaseAmount = _deinflate(step.amountIn, true), true);
            }
        }

        if (state.liquidity > 0) {
            uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128();
            fpGlobal.update(
                swapVTokenForVBase ? int256(vTokenAmount) : -int256(vTokenAmount), // when trader goes long, LP goes short
                state.liquidity,
                _blockTimestamp(),
                priceX128,
                vTokenAmount.mulDiv(FixedPoint128.Q128, vBaseAmount) // TODO change to TWAP
            );

            sumFeeGlobalX128 += lpFeesInVBase.mulDiv(FixedPoint128.Q128, state.liquidity);
        }

        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                ticksExtended.cross(step.tickNext, fpGlobal, sumFeeGlobalX128);
            }
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external virtual {
        require(msg.sender == address(vPool));
        if (amount0Delta > 0) {
            IVToken(vPool.token0()).mint(address(vPool), uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            IVToken(vPool.token1()).mint(address(vPool), uint256(amount1Delta));
        }
    }

    // for updating global funding payment
    function zeroSwap() external {
        uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128();
        fpGlobal.update(0, 1, _blockTimestamp(), priceX128, vPool.getTwapSqrtPrice(timeHorizon).toPriceX128());
    }

    function _updateTicks(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickCurrent
    ) private {
        FundingPayment.Info memory _fpGlobal = fpGlobal; // SLOAD
        uint256 _sumFeeGlobalX128 = sumFeeGlobalX128;

        // if we need to update the ticks, do it
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = ticksExtended.update(
                tickLower,
                tickCurrent,
                liquidityDelta,
                _fpGlobal.sumAX128,
                _fpGlobal.sumBX128,
                _fpGlobal.sumFpX128,
                _sumFeeGlobalX128,
                vPool
            );
            flippedUpper = ticksExtended.update(
                tickUpper,
                tickCurrent,
                liquidityDelta,
                _fpGlobal.sumAX128,
                _fpGlobal.sumBX128,
                _fpGlobal.sumFpX128,
                _sumFeeGlobalX128,
                vPool
            );
        }

        // clear any tick data that is no longer needed
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticksExtended.clear(tickLower);
            }
            if (flippedUpper) {
                ticksExtended.clear(tickUpper);
            }
        }
    }

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) external returns (int256 basePrincipal, int256 vTokenPrincipal) {
        _updateTicks(tickLower, tickUpper, liquidityDelta, vPool.tickCurrent());
        if (liquidityDelta > 0) {
            (uint256 _amount0, uint256 _amount1) = vPool.mint({
                recipient: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidityDelta),
                data: ''
            });
            vTokenPrincipal = _amount0.toInt256();
            basePrincipal = _amount1.toInt256();
        } else {
            (uint256 _amount0, uint256 _amount1) = vPool.burn({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidityDelta * -1)
            });
            vTokenPrincipal = _amount0.toInt256() * -1;
            basePrincipal = _amount1.toInt256() * -1;
            // review : do we want final amount here with fees included or just the am for liq ?
            // As per spec its am for liq only
            collect(tickLower, tickUpper);
        }
    }

    function uniswapV3MintCallback(
        uint256 vTokenAmount,
        uint256 vBaseAmount,
        bytes calldata
    ) external override {
        require(msg.sender == address(vPool));
        if (vBaseAmount > 0) IVBase(constants.VBASE_ADDRESS).mint(msg.sender, vBaseAmount);
        if (vTokenAmount > 0) vToken.iface().mint(msg.sender, vTokenAmount);
    }

    function collect(int24 tickLower, int24 tickUpper) internal {
        // (uint256 amount0, uint256 amount1) =
        vPool.collect({
            recipient: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Requested: type(uint128).max,
            amount1Requested: type(uint128).max
        });

        _vBurn();
    }

    function _vBurn() internal {
        uint256 vBaseBal = IVBase(constants.VBASE_ADDRESS).balanceOf(address(this));
        if (vBaseBal > 0) {
            IVBase(constants.VBASE_ADDRESS).burn(vBaseBal);
        }
        uint256 vTokenBal = vToken.iface().balanceOf(address(this));
        if (vTokenBal > 0) {
            vToken.iface().burn(vTokenBal);
        }
    }

    function getSumAX128() external view returns (int256) {
        return fpGlobal.sumAX128;
    }

    // used to set time in tests
    function _blockTimestamp() internal view returns (uint48) {
        return uint48(block.timestamp);
    }
}
