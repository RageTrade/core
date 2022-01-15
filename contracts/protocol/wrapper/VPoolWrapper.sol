//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3MintCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IVBase } from '../../interfaces/IVBase.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';

import { VTokenAddress, VTokenLib } from '../../libraries/VTokenLib.sol';
import { FundingPayment } from '../../libraries/FundingPayment.sol';
import { SimulateSwap } from '../../libraries/SimulateSwap.sol';
import { Tick } from '../../libraries/Tick.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { SignedFullMath } from '../../libraries/SignedFullMath.sol';
import { UniswapV3PoolHelper } from '../../libraries/UniswapV3PoolHelper.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback, IUniswapV3SwapCallback, Initializable {
    using FullMath for uint256;
    using FundingPayment for FundingPayment.Info;
    using SignedMath for int256;
    using SignedFullMath for int256;

    using PriceMath for uint160;
    using SafeCast for uint256;
    using SimulateSwap for IUniswapV3Pool;
    using Tick for IUniswapV3Pool;
    using Tick for mapping(int24 => Tick.Info);
    using UniswapV3PoolHelper for IUniswapV3Pool;
    using VTokenLib for VTokenAddress;

    IClearingHouse public clearingHouse;
    IVToken public vToken;
    IVBase public vBase;
    IUniswapV3Pool public vPool;

    uint24 public uniswapFeePips; // fee collected by Uniswap
    uint24 public liquidityFeePips; // fee paid to liquidity providers, in 1e6
    uint24 public protocolFeePips; // fee paid to DAO treasury

    uint256 public accruedProtocolFee;

    FundingPayment.Info public fpGlobal;
    uint256 public sumFeeGlobalX128; // extendedFeeGrowthGlobalX128;

    mapping(int24 => Tick.Info) public ticksExtended;

    error NotClearingHouse();
    error NotGovernance();

    modifier onlyClearingHouse() {
        if (msg.sender != address(clearingHouse)) {
            revert NotClearingHouse();
        }
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != clearingHouse.governance()) {
            revert NotGovernance();
        }
        _;
    }

    /**
        PLATFORM FUNCTIONS
     */

    function VPoolWrapper__init(InitializeVPoolWrapperParams calldata params) external initializer {
        clearingHouse = params.clearingHouse;
        vToken = params.vTokenAddress;
        vBase = params.vBase;
        vPool = params.vPool;

        liquidityFeePips = params.liquidityFeePips;
        protocolFeePips = params.protocolFeePips;
        uniswapFeePips = params.UNISWAP_V3_DEFAULT_FEE_TIER;

        // initializes the funding payment state
        fpGlobal.update(0, 1, _blockTimestamp(), 1, 1);
    }

    function collectAccruedProtocolFee() external onlyClearingHouse returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = accruedProtocolFee - 1;
        accruedProtocolFee = 1;
    }

    // for updating global funding payment
    function updateGlobalFundingState() public {
        (uint256 realPriceX128, uint256 virtualPriceX128) = clearingHouse.getTwapSqrtPricesForSetDuration(
            VTokenAddress.wrap(address(vToken)) // TODO use IVToken as custom type
        );
        fpGlobal.update(0, 1, _blockTimestamp(), realPriceX128, virtualPriceX128);
    }

    /**
        ADMIN FUNCTIONS
     */

    function setLiquidityFee(uint24 liquidityFeePips_) external onlyGovernance {
        liquidityFeePips = liquidityFeePips_;
    }

    function setProtocolFee(uint24 protocolFeePips_) external onlyGovernance {
        protocolFeePips = protocolFeePips_;
    }

    /**
        EXTERNAL UTILITY METHODS
     */

    /// @notice swaps token
    /// @param amount: positive means long, negative means short
    /// @param isNotional: true means amountSpecified is dollar amount
    /// @param sqrtPriceLimitX96: The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap.
    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimitX96,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount) {
        // case isNotional true
        // amountSpecified is positive
        return swap(amount < 0, isNotional ? amount : -amount, sqrtPriceLimitX96);
    }

    /// @notice Swap vToken for vBase, or vBase for vToken
    /// @param swapVTokenForVBase: The direction of the swap, true for vToken to vBase, false for vBase to vToken
    /// @param amountSpecified: The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param sqrtPriceLimitX96: The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap.
    function swap(
        bool swapVTokenForVBase, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 vTokenIn, int256 vBaseIn) {
        bool exactIn = amountSpecified >= 0;

        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = swapVTokenForVBase ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }

        uint256 liquidityFees;
        uint256 protocolFees;

        // inflate or deinfate to undo uniswap fees if necessary, and account for our fees
        if (exactIn) {
            if (swapVTokenForVBase) {
                // CASE: exactIn vToken
                // fee: not now, will collect fee in vBase after swap
                // inflate: for undoing the uniswap fees
                amountSpecified = _inflate(amountSpecified);
            } else {
                // CASE: exactIn vBase
                // fee: remove fee and do smaller swap, so trader gets less vTokens
                // here, amountSpecified == swap amount + fee
                (liquidityFees, protocolFees) = _calculateFees(amountSpecified, AmountTypeEnum.VBASE_AMOUNT_PLUS_FEES);
                amountSpecified = _includeFees(
                    amountSpecified,
                    liquidityFees + protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
                // inflate: uniswap will collect fee so inflate to undo it
                amountSpecified = _inflate(amountSpecified);
            }
        } else {
            if (!swapVTokenForVBase) {
                // CASE: exactOut vToken
                // fee: no need to collect fee as we want to collect fee in vBase later
                // inflate: no need to inflate as uniswap collects fees in tokenIn
            } else {
                // CASE: exactOut vBase
                // fee: buy more vBase (short more vToken) so that fee can be removed in vBase
                // here, amountSpecified + fee == swap amount
                (liquidityFees, protocolFees) = _calculateFees(amountSpecified, AmountTypeEnum.VBASE_AMOUNT_MINUS_FEES);
                amountSpecified = _includeFees(amountSpecified, liquidityFees + protocolFees, IncludeFeeEnum.ADD_FEE);
            }
        }

        {
            // simulate swap and update our tick states
            (int256 vTokenIn_simulated, int256 vBaseIn_simulated) = vPool.simulateSwap(
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

        // swap is done so now adjusting vTokenIn and vBaseIn amounts to remove uniswap fees and add our fees
        if (exactIn) {
            if (swapVTokenForVBase) {
                // CASE: exactIn vToken
                // deinflate: vToken amount was inflated so that uniswap can collect fee
                vTokenIn = _deinflate(vTokenIn);
                // fee: collect the fee, give less vBase to trader
                // here, vBaseIn == swap amount
                (liquidityFees, protocolFees) = _calculateFees(vBaseIn, AmountTypeEnum.ZERO_FEE_VBASE_AMOUNT);
                vBaseIn = _includeFees(vBaseIn, liquidityFees + protocolFees, IncludeFeeEnum.SUBTRACT_FEE);
            } else {
                // CASE: exactIn vBase
                // deinflate: vBase amount was inflated, hence need to deinflate for generating final statement
                vBaseIn = _deinflate(vBaseIn);
                // fee: fee is already removed before swap, lets include it to the final bill, so that trader pays for it
                vBaseIn = _includeFees(vBaseIn, liquidityFees + protocolFees, IncludeFeeEnum.ADD_FEE);
            }
        } else {
            if (!swapVTokenForVBase) {
                // CASE: exactOut vToken
                // deinflate: uniswap want to collect fee in vBase and hence ask more, so need to deinflate it
                vBaseIn = _deinflate(vBaseIn);
                // fee: collecting fees in vBase
                // here, vBaseIn == swap amount
                (liquidityFees, protocolFees) = _calculateFees(vBaseIn, AmountTypeEnum.ZERO_FEE_VBASE_AMOUNT);
                vBaseIn = _includeFees(vBaseIn, liquidityFees + protocolFees, IncludeFeeEnum.ADD_FEE);
            } else {
                // CASE: exactOut vBase
                // deinflate: uniswap want to collect fee in vToken and hence ask more, so need to deinflate it
                vTokenIn = _deinflate(vTokenIn);
                // fee: already calculated before, subtract now
                vBaseIn = _includeFees(vBaseIn, liquidityFees + protocolFees, IncludeFeeEnum.SUBTRACT_FEE);
            }
        }

        // record the protocol fee, for withdrawal in future
        accruedProtocolFee += protocolFees;

        // burn the tokens received from the swap
        _vBurn();

        emit Swap(vTokenIn, vBaseIn, liquidityFees, protocolFees);
    }

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    )
        external
        returns (
            int256 basePrincipal,
            int256 vTokenPrincipal,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        updateGlobalFundingState();
        wrapperValuesInside = _updateTicks(tickLower, tickUpper, liquidityDelta, vPool.tickCurrent());
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
            _collect(tickLower, tickUpper);
        }
    }

    /**
        UNISWAP V3 POOL CALLBACkS
     */

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

    function uniswapV3MintCallback(
        uint256 vTokenAmount,
        uint256 vBaseAmount,
        bytes calldata
    ) external override {
        require(msg.sender == address(vPool));
        if (vBaseAmount > 0) vBase.mint(msg.sender, vBaseAmount);
        if (vTokenAmount > 0) vToken.mint(msg.sender, vTokenAmount);
    }

    /**
        VIEW METHODS
     */

    function getSumAX128() external view returns (int256) {
        return fpGlobal.sumAX128;
    }

    function getExtrapolatedSumAX128() public view returns (int256) {
        (uint256 realPriceX128, uint256 virtualPriceX128) = clearingHouse.getTwapSqrtPricesForSetDuration(
            VTokenAddress.wrap(address(vToken)) // TODO use IVToken as custom type
        );
        return
            FundingPayment.extrapolatedSumAX128(
                fpGlobal.sumAX128,
                fpGlobal.timestampLast,
                _blockTimestamp(),
                realPriceX128,
                virtualPriceX128
            );
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;
        wrapperValuesInside.sumAX128 = _fpGlobal.sumAX128;
        (
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        ) = ticksExtended.getTickExtendedStateInside(tickLower, tickUpper, currentTick, _fpGlobal, sumFeeGlobalX128);
    }

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        (, int24 currentTick, , , , , ) = vPool.slot0();
        FundingPayment.Info memory _fpGlobal = fpGlobal;

        ///@dev update sumA and sumFP to extrapolated values according to current timestamp
        _fpGlobal.sumAX128 = getExtrapolatedSumAX128();
        _fpGlobal.sumFpX128 = FundingPayment.extrapolatedSumFpX128(
            fpGlobal.sumAX128,
            fpGlobal.sumBX128,
            fpGlobal.sumFpX128,
            _fpGlobal.sumAX128
        );

        wrapperValuesInside.sumAX128 = _fpGlobal.sumAX128;
        (
            wrapperValuesInside.sumBInsideX128,
            wrapperValuesInside.sumFpInsideX128,
            wrapperValuesInside.sumFeeInsideX128
        ) = ticksExtended.getTickExtendedStateInside(tickLower, tickUpper, currentTick, _fpGlobal, sumFeeGlobalX128);
    }

    /**
        INTERNAL HELPERS
     */

    function _collect(int24 tickLower, int24 tickUpper) internal {
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

    function _onSwapStep(
        bool swapVTokenForVBase,
        SimulateSwap.SwapCache memory,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        // these vBase and vToken amounts are zero fee swap amounts (fee collected by uniswaop is ignored and burned later)
        (uint256 vTokenAmount, uint256 vBaseAmount) = swapVTokenForVBase
            ? (step.amountIn, step.amountOut)
            : (step.amountOut, step.amountIn);

        // here, vBaseAmount == swap amount
        (uint256 liquidityFees, ) = _calculateFees(int256(vBaseAmount), AmountTypeEnum.ZERO_FEE_VBASE_AMOUNT);

        // base amount with fees
        // vBaseAmount = _includeFees(
        //     vBaseAmount,
        //     liquidityFees + protocolFees,
        //     swapVTokenForVBase ? IncludeFeeEnum.SUBTRACT_FEE : IncludeFeeEnum.ADD_FEE
        // );

        if (state.liquidity > 0 && vTokenAmount > 0) {
            (uint256 realPriceX128, uint256 virtualPriceX128) = clearingHouse.getTwapSqrtPricesForSetDuration(
                VTokenAddress.wrap(address(vToken)) // TODO use IVToken as custom type
            );
            fpGlobal.update(
                swapVTokenForVBase ? int256(vTokenAmount) : -int256(vTokenAmount), // when trader goes long, LP goes short
                state.liquidity,
                _blockTimestamp(),
                realPriceX128,
                virtualPriceX128
            );

            sumFeeGlobalX128 += liquidityFees.mulDiv(FixedPoint128.Q128, state.liquidity);
        }

        // if we have reached the end price of tick
        if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
            // if the tick is initialized, run the tick transition
            if (step.initialized) {
                ticksExtended.cross(step.tickNext, fpGlobal, sumFeeGlobalX128);
            }
        }
    }

    function _updateTicks(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tickCurrent
    ) private returns (WrapperValuesInside memory wrapperValuesInside) {
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

        wrapperValuesInside = getValuesInside(tickLower, tickUpper);

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

    function _vBurn() internal {
        uint256 vBaseBal = vBase.balanceOf(address(this));
        if (vBaseBal > 0) {
            vBase.burn(vBaseBal);
        }
        uint256 vTokenBal = vToken.balanceOf(address(this));
        if (vTokenBal > 0) {
            vToken.burn(vTokenBal);
        }
    }

    // used to set time in tests
    function _blockTimestamp() internal view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    function _inflate(int256 amount) internal view returns (int256 inflated) {
        int256 fees = (amount * int256(uint256(uniswapFeePips))) / int24(1e6 - uniswapFeePips) + 1; // round up
        inflated = amount + fees;
    }

    function _deinflate(int256 inflated) internal view returns (int256 amount) {
        amount = (inflated * int24(1e6 - uniswapFeePips)) / 1e6;
    }

    enum AmountTypeEnum {
        ZERO_FEE_VBASE_AMOUNT,
        VBASE_AMOUNT_MINUS_FEES,
        VBASE_AMOUNT_PLUS_FEES
    }

    function _calculateFees(int256 amount, AmountTypeEnum amountTypeEnum)
        internal
        view
        returns (uint256 liquidityFees, uint256 protocolFees)
    {
        uint256 amountAbs = uint256(amount.abs());
        if (amountTypeEnum == AmountTypeEnum.VBASE_AMOUNT_MINUS_FEES) {
            // when amount is already subtracted by fees, we need to scale it up, so that
            // on calculating and subtracting fees on the scaled up value, we should get same amount
            amountAbs = (amountAbs * 1e6) / uint256(1e6 - liquidityFeePips - protocolFeePips);
        } else if (amountTypeEnum == AmountTypeEnum.VBASE_AMOUNT_PLUS_FEES) {
            // when amount is already added with fees, we need to scale it down, so that
            // on calculating and adding fees on the scaled down value, we should get same amount
            amountAbs = (amountAbs * 1e6) / uint256(1e6 + liquidityFeePips + protocolFeePips);
        }
        uint256 fees = (amountAbs * (liquidityFeePips + protocolFeePips)) / 1e6 + 1; // round up
        liquidityFees = (amountAbs * liquidityFeePips) / 1e6 + 1; // round up
        protocolFees = fees - liquidityFees;
    }

    enum IncludeFeeEnum {
        ADD_FEE,
        SUBTRACT_FEE
    }

    function _includeFees(
        int256 amount,
        uint256 fees,
        IncludeFeeEnum includeFeeEnum
    ) internal pure returns (int256 amountAfterFees) {
        if ((amount > 0) == (includeFeeEnum == IncludeFeeEnum.ADD_FEE)) {
            amountAfterFees = amount + int256(fees);
        } else {
            amountAfterFees = amount - int256(fees);
        }
    }
}
