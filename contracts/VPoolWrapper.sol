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
    bool public immutable isToken0;

    // fee collected by Uniswap from traders and given to LPs
    uint24 public immutable uniswapFee;

    // extra fee collected here from traders and given to LPs
    // useful when pool wants LP fees 0.1% desired instead of 0.05% or 0.3%
    uint24 public extendedFee;

    // fee collected here from traders and given to Protocol/DAO
    uint24 public protocolFee;
    uint256 public accruedProtocolFee;

    bool public whitelisted;

    // oracle for real prices
    IOracle public oracle;

    FundingPayment.Info public fpGlobal;
    uint256 public sumExFeeGlobalX128; // extendedFeeGrowthGlobalX128;
    mapping(int24 => Tick.Info) public ticksExtended;

    Constants public constants;

    constructor() {
        address vTokenAddress;
        address vPoolAddress;
        (
            vTokenAddress,
            vPoolAddress,
            extendedFee,
            protocolFee,
            initialMarginRatio,
            maintainanceMarginRatio,
            timeHorizon,
            whitelisted,
            constants
        ) = IVPoolWrapperDeployer(msg.sender).parameters();
        vToken = VTokenAddress.wrap(vTokenAddress);
        vPool = IUniswapV3Pool(vPoolAddress);
        uniswapFee = vPool.fee();
        isToken0 = vToken.isToken0(constants);
        // console.log('isToken0', isToken0 ? 'true' : 'false');
    }

    // TODO restrict this to governance
    function setOracle(address oracle_) external {
        oracle = IOracle(oracle_);
    }

    // TODO restrict this to governance
    function setWhitelisted(bool whitelisted_) external {
        whitelisted = whitelisted_;
    }

    // TODO restrict this to governance
    function setExtendedFee(uint24 extendedFee_) external {
        extendedFee = extendedFee_;
    }

    // TODO restrict this to governance
    function setProtocolFee(uint24 protocolFee_) external {
        protocolFee = protocolFee_;
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

        uint256 sumExFeeInsideX128;
        (sumBInsideX128, sumFpInsideX128, sumExFeeInsideX128) = ticksExtended.getTickExtendedStateInside(
            tickLower,
            tickUpper,
            currentTick,
            _fpGlobal,
            sumExFeeGlobalX128
        );
        uint256 uniswapFeeInsideX128 = vPool.getUniswapFeeGrowthInside(tickLower, tickUpper, currentTick, isToken0);
        sumFeeInsideX128 = uniswapFeeInsideX128 + sumExFeeInsideX128;
    }

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount) {
        (vBaseAmount, vTokenAmount) = swap(isNotional, amount, sqrtPriceLimit);
    }

    /// @notice swaps token
    /// @param isNotional: true for long or close short. false for short or close long.
    /// @param amountSpecified: vtoken amount as positive or usdc amount as negative.
    /// @param sqrtPriceLimitX96: price limit
    function swap(
        bool isNotional,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 vBaseIn, int256 vTokenIn) {
        bool buyVToken = amountSpecified > 0;

        bool zeroForOne = isToken0 != (buyVToken);

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        uint256 protocolFeeCollected;
        /// @dev if specified dollars then apply the protocol fee before swap
        if (isNotional) {
            protocolFeeCollected = (uint256(amountSpecified.abs()) * protocolFee) / 1e6;
            amountSpecified -= int256(protocolFeeCollected);
            if (buyVToken) {
                amountSpecified = (amountSpecified * int24(1e6 - uniswapFee - extendedFee)) / int24(1e6 - uniswapFee);
            }
        } else {
            amountSpecified = -amountSpecified;
        }

        if (!buyVToken) {
            /// @dev inflate (bcoz trader is selling then uniswap collects fee in vtoken)
            amountSpecified = (amountSpecified * 1e6) / int24(1e6 - uniswapFee - extendedFee);
        }

        {
            (int256 amount0_simulated, int256 amount1_simulated, uint256 protocolFee) = vPool.simulateSwap(
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96,
                _onSwapStep
            );

            /// @dev execute trade on uniswap
            (int256 amount0, int256 amount1) = vPool.swap(
                address(this),
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96,
                ''
            );

            // TODO remove this check in production
            assert(amount0_simulated == amount0 && amount1_simulated == amount1);

            (vBaseIn, vTokenIn) = vToken.flip(amount0, amount1, constants);
        }

        if (buyVToken) {
            vBaseIn = (vBaseIn * int24(1e6 - uniswapFee)) / int24(1e6 - uniswapFee - extendedFee); // negative
        } else {
            /// @dev de-inflate
            vBaseIn = (vBaseIn * int24(1e6 - uniswapFee - extendedFee)) / 1e6 - 1; // negative
            vTokenIn = (vTokenIn * int24(1e6 - uniswapFee - extendedFee)) / 1e6 + 1; // positive
        }

        /// @dev if specified vtoken then apply the protocol fee after swap
        if (!isNotional) {
            protocolFeeCollected = uint256(vBaseIn.abs().mulDiv(protocolFee, 1e6));
        }

        /// @dev user pays protocol fee so add it as in
        vBaseIn += int256(protocolFeeCollected);

        /// @dev increment the accrual variable
        accruedProtocolFee += protocolFeeCollected;

        /// @dev burn the tokens received from the swap
        _vBurn();
    }

    function _onSwapStep(
        bool zeroForOne,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal returns (uint256 protocolFee) {
        bool buyVToken = isToken0 != zeroForOne;
        (uint256 vBaseAmount, uint256 vTokenAmount) = buyVToken
            ? (step.amountIn, step.amountOut)
            : (step.amountOut, step.amountIn);

        if (state.liquidity > 0 && vBaseAmount > 0) {
            uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128(isToken0);
            fpGlobal.update(
                buyVToken ? int256(vTokenAmount) : -int256(vTokenAmount),
                state.liquidity,
                cache.blockTimestamp,
                priceX128,
                vTokenAmount.mulDiv(FixedPoint128.Q128, vBaseAmount) // TODO change to TWAP
            );
            //
            if (buyVToken) {
                sumExFeeGlobalX128 += vBaseAmount.mulDiv(extendedFee, 1e6 - extendedFee).mulDiv(
                    FixedPoint128.Q128,
                    state.liquidity
                );
            } else {
                sumExFeeGlobalX128 += vBaseAmount
                    .mulDiv(uniswapFee + extendedFee, 1e6 - uniswapFee - extendedFee)
                    .mulDiv(FixedPoint128.Q128, state.liquidity);
            }
        }

        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                ticksExtended.cross(step.tickNext, fpGlobal, sumExFeeGlobalX128);
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
        uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128(isToken0);
        fpGlobal.update(
            0,
            1,
            uint48(block.timestamp),
            priceX128,
            vPool.getTwapSqrtPrice(timeHorizon).toPriceX128(isToken0)
        );
    }

    function _updateTicks(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickCurrent
    ) private {
        FundingPayment.Info memory _fpGlobal = fpGlobal; // SLOAD
        uint256 _sumExFeeGlobalX128 = sumExFeeGlobalX128;

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
                _sumExFeeGlobalX128,
                vPool
            );
            flippedUpper = ticksExtended.update(
                tickUpper,
                tickCurrent,
                liquidityDelta,
                _fpGlobal.sumAX128,
                _fpGlobal.sumBX128,
                _fpGlobal.sumFpX128,
                _sumExFeeGlobalX128,
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
        int256 amount0;
        int256 amount1;
        if (liquidityDelta > 0) {
            (uint256 _amount0, uint256 _amount1) = vPool.mint({
                recipient: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidityDelta),
                data: ''
            });
            amount0 = _amount0.toInt256();
            amount1 = _amount1.toInt256();
        } else {
            (uint256 _amount0, uint256 _amount1) = vPool.burn({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidityDelta * -1)
            });
            amount0 = _amount0.toInt256() * -1;
            amount1 = _amount1.toInt256() * -1;
            // review : do we want final amount here with fees included or just the am for liq ?
            // As per spec its am for liq only
            collect(tickLower, tickUpper);
        }
        (basePrincipal, vTokenPrincipal) = vToken.flip(amount0, amount1, constants);
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata
    ) external override {
        require(msg.sender == address(vPool));
        (uint256 vBaseAmount, uint256 vTokenAmount) = vToken.flip(amount0, amount1, constants);
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
}
