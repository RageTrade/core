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
import { Oracle } from './libraries/Oracle.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SignedMath for int256;
    using PriceMath for uint160;
    using SafeCast for uint256;
    using Oracle for IUniswapV3Pool;
    using SimulateSwap for IUniswapV3Pool;
    using Tick for IUniswapV3Pool;
    using Tick for mapping(int24 => Tick.Info);
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
    uint256 public extendedFeeGrowthGlobalX128;
    mapping(int24 => Tick.Info) public extendedTicks;

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
            uint256 uniswapFeeInsideX128,
            uint256 extendedFeeInsideX128
        )
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;
        sumAX128 = _fpGlobal.sumAX128;
        sumBInsideX128 = extendedTicks.getNetPositionInside(tickLower, tickUpper, currentTick, _fpGlobal.sumBX128);
        sumFpInsideX128 = extendedTicks.getFundingPaymentGrowthInside(
            tickLower,
            tickUpper,
            currentTick,
            _fpGlobal.sumAX128,
            _fpGlobal.sumFpX128
        );
        uniswapFeeInsideX128 = vPool.getUniswapFeeGrowthInside(tickLower, tickUpper, currentTick, isToken0);
        extendedFeeInsideX128 = extendedTicks.getExtendedFeeGrowthInside(
            tickLower,
            tickUpper,
            currentTick,
            extendedFeeGrowthGlobalX128
        );
    }

    function swapTokenNotional(int256 vBaseAmount) external returns (int256 vTokenAmount) {
        (, vTokenAmount) = swap(vBaseAmount > 0, -vBaseAmount.abs(), 0);
    }

    function swapTokenAmount(int256 vTokenAmount) external returns (int256 vBaseAmount) {
        (vBaseAmount, ) = swap(vTokenAmount > 0, vTokenAmount.abs(), 0);
    }

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount) {
        (vBaseAmount, vTokenAmount) = swap(amount > 0, (isNotional ? -amount.abs() : amount.abs()), sqrtPriceLimit);
    }

    /// @notice swaps token
    /// @param buyVToken: true for long or close short. false for short or close long.
    /// @param amountSpecified: vtoken amount as positive or usdc amount as negative.
    /// @param sqrtPriceLimitX96: price limit
    function swap(
        bool buyVToken,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 vBaseIn, int256 vTokenIn) {
        // TODO: remove this after testing
        // console.log("buyVToken");
        // console.log(buyVToken);
        // console.log("amountSpecified");
        // console.logInt(amountSpecified);

        // console.log("sqrtPriceLimitX96");
        // console.log(sqrtPriceLimitX96);

        bool zeroForOne = isToken0 != buyVToken;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        bool isVTokenSpecified = amountSpecified > 0;

        uint256 protocolFeeCollected;
        /// @dev if specified dollars then apply the protocol fee before swap
        if (amountSpecified < 0) {
            protocolFeeCollected = (uint256(-amountSpecified) * protocolFee) / 1e6;
            if (buyVToken) {
                /// @dev buy vtoken with less vbase (consumes vbase)
                amountSpecified += int256(protocolFeeCollected);
            } else {
                /// @dev sell vtoken with more vbase (gives vbase)
                amountSpecified -= int256(protocolFeeCollected);
            }
        }

        if (buyVToken) {
            /// @dev trader is buying vtoken then exact output
            if (amountSpecified > 0) {
                amountSpecified = -amountSpecified;
            } else {
                amountSpecified = (-amountSpecified * int24(1e6 - uniswapFee - extendedFee)) / int24(1e6 - uniswapFee);
            }
        } else {
            /// @dev inflate (bcoz trader is selling then uniswap collects fee in vtoken)
            amountSpecified = (amountSpecified * 1e6) / int24(1e6 - uniswapFee - extendedFee);
        }

        {
            // TODO: remove this after testing
            // if (amountSpecified > 0) {
            //     console.log('amountSpecified', uint256(amountSpecified));
            // } else {
            //     console.log('amountSpecified -', uint256(-amountSpecified));
            // }
            /// @dev updates global and tick states
            (int256 amount0_simulated, int256 amount1_simulated) = vPool.simulateSwap(
                zeroForOne,
                amountSpecified,
                sqrtPriceLimitX96,
                _onSwapSwap
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
        if (isVTokenSpecified) {
            protocolFeeCollected = (uint256(vBaseIn.abs()) * protocolFee) / 1e6;
        }

        /// @dev user pays protocol fee so add it as in
        vBaseIn += int256(protocolFeeCollected);

        /// @dev increment the accrual variable
        accruedProtocolFee += protocolFeeCollected;

        /// @dev burn the tokens received from the swap
        _vBurn();
    }

    function _onSwapSwap(
        bool zeroForOne,
        SimulateSwap.SwapCache memory cache,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        bool buyVToken = isToken0 != zeroForOne;
        (uint256 vBaseAmount, uint256 vTokenAmount) = buyVToken
            ? (step.amountIn, step.amountOut)
            : (step.amountOut, step.amountIn);

        // TODO: remove this after testing
        // console.log('');
        // if (state.amountSpecifiedRemaining > 0) {
        //     console.log('state.amountSpecifiedRemaining', uint256(state.amountSpecifiedRemaining));
        // } else {
        //     console.log('state.amountSpecifiedRemaining -', uint256(-state.amountSpecifiedRemaining));
        // }
        // console.log('step.sqrtPriceNextX96', uint256(step.sqrtPriceNextX96));
        // if (state.tick > 0) {
        //     console.log('state.tick', uint24(state.tick));
        // } else {
        //     console.log('state.tick -', uint24(-state.tick));
        // }
        // if (step.tickNext > 0) {
        //     console.log('state.tickNext', uint24(step.tickNext));
        // } else {
        //     console.log('state.tickNext -', uint24(-step.tickNext));
        // }
        // console.log('step vBaseAmount', vBaseAmount);
        // console.log('step vTokenAmount', vTokenAmount);
        if (state.liquidity > 0 && vBaseAmount > 0) {
            uint256 priceX128 = oracle.getTwapSqrtPriceX96(1 hours).toPriceX128(isToken0);
            fpGlobal.update(
                buyVToken ? int256(vTokenAmount) : -int256(vTokenAmount),
                state.liquidity,
                cache.blockTimestamp,
                priceX128,
                vTokenAmount.mulDiv(FixedPoint128.Q128, vBaseAmount) // TODO change to TWAP
            );
            //
            if (buyVToken) {
                extendedFeeGrowthGlobalX128 += vBaseAmount.mulDiv(extendedFee, 1e6 - extendedFee).mulDiv(
                    FixedPoint128.Q128,
                    state.liquidity
                );
            } else {
                extendedFeeGrowthGlobalX128 += vBaseAmount
                    .mulDiv(uniswapFee + extendedFee, 1e6 - uniswapFee - extendedFee)
                    .mulDiv(FixedPoint128.Q128, state.liquidity);
            }
        }

        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                extendedTicks.cross(step.tickNext, fpGlobal, extendedFeeGrowthGlobalX128);
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
        uint256 priceX128 = oracle.getTwapSqrtPriceX96(1 hours).toPriceX128(isToken0);
        fpGlobal.update(
            0,
            1,
            uint48(block.timestamp),
            priceX128,
            vPool.getTwapSqrtPrice(1 hours).toPriceX128(isToken0)
        );
    }

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external returns (int256 basePrincipal, int256 vTokenPrincipal) {
        int256 amount0;
        int256 amount1;
        if (liquidity > 0) {
            (uint256 _amount0, uint256 _amount1) = vPool.mint({
                recipient: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity),
                data: ''
            });
            amount0 = _amount0.toInt256();
            amount1 = _amount1.toInt256();
        } else {
            (uint256 _amount0, uint256 _amount1) = vPool.burn({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity * -1)
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
