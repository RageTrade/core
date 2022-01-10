//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolWrapperDeployer.sol';
import { VTokenAddress, VTokenLib, Constants } from './libraries/VTokenLib.sol';
import '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core-0.8-support/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/IVBase.sol';
import './interfaces/IVToken.sol';
import { IOracle } from './interfaces/IOracle.sol';
import { IVToken } from './interfaces/IVToken.sol';
import { IUniswapV3PoolDeployer } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3PoolDeployer.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FundingPayment } from './libraries/FundingPayment.sol';
import { SimulateSwap } from './libraries/SimulateSwap.sol';
import { Tick } from './libraries/Tick.sol';
import { TickMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { PriceMath } from './libraries/PriceMath.sol';
import { SignedMath } from './libraries/SignedMath.sol';
import { SignedFullMath } from './libraries/SignedFullMath.sol';
import { UniswapV3PoolHelper } from './libraries/UniswapV3PoolHelper.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback, IUniswapV3SwapCallback {
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
        address oracleAddress;
        (
            vTokenAddress,
            vPoolAddress,
            oracleAddress,
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
        oracle = IOracle(oracleAddress); // TODO: take oracle from clearing house
        uniswapFeePips = vPool.fee();

        // initializes the funding payment variable
        zeroSwap();
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
                (liquidityFees, protocolFees) = _calculateFees(amountSpecified, CalcFeeEnum.CALCULATE_ON_AMOUNT);
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
                (liquidityFees, protocolFees) = _calculateFees(amountSpecified, CalcFeeEnum.CALCULATE_ON_SCALED);
                amountSpecified = _includeFees(amountSpecified, liquidityFees + protocolFees, IncludeFeeEnum.ADD_FEE);
                // TODO: inflate: no need to inflate now but uniswap will collect fee in vToken, so need to inflate it later
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
                (liquidityFees, protocolFees) = _calculateFees(vBaseIn, CalcFeeEnum.CALCULATE_ON_AMOUNT);
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
                (liquidityFees, protocolFees) = _calculateFees(vBaseIn, CalcFeeEnum.CALCULATE_ON_AMOUNT);
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

    function _onSwapStep(
        bool swapVTokenForVBase,
        SimulateSwap.SwapCache memory,
        SimulateSwap.SwapState memory state,
        SimulateSwap.StepComputations memory step
    ) internal {
        bool exactIn = state.amountCalculated < 0;

        uint256 liquidityFees;
        // these vBase and vToken amounts are zero fee swap (fee collected by uniswaop is ignored and burned later)
        (uint256 vTokenAmount, uint256 vBaseAmount) = swapVTokenForVBase
            ? (step.amountIn, step.amountOut)
            : (step.amountOut, step.amountIn);

        if (exactIn) {
            if (swapVTokenForVBase) {
                // CASE: exactIn vToken
                uint256 _protocolFees;
                (liquidityFees, _protocolFees) = _calculateFees(int256(vBaseAmount), CalcFeeEnum.CALCULATE_ON_AMOUNT);
                vBaseAmount = _includeFees(vBaseAmount, liquidityFees + _protocolFees, IncludeFeeEnum.SUBTRACT_FEE);
            } else {
                // CASE: exactIn vBase
                uint256 _protocolFees;
                (liquidityFees, _protocolFees) = _calculateFees(int256(vBaseAmount), CalcFeeEnum.CALCULATE_ON_SCALED);
                vBaseAmount = _includeFees(vBaseAmount, liquidityFees + _protocolFees, IncludeFeeEnum.ADD_FEE);
            }
        } else {
            if (!swapVTokenForVBase) {
                // CASE: exactOut vToken
                uint256 _protocolFees;
                (liquidityFees, _protocolFees) = _calculateFees(int256(vBaseAmount), CalcFeeEnum.CALCULATE_ON_AMOUNT);
                vBaseAmount = _includeFees(vBaseAmount, liquidityFees + _protocolFees, IncludeFeeEnum.ADD_FEE);
            } else {
                // CASE: exactOut vBase
                uint256 _protocolFees;
                (liquidityFees, _protocolFees) = _calculateFees(int256(vBaseAmount), CalcFeeEnum.CALCULATE_ON_AMOUNT);
                vBaseAmount = _includeFees(vBaseAmount, liquidityFees + _protocolFees, IncludeFeeEnum.SUBTRACT_FEE);
            }
        }

        if (state.liquidity > 0 && vTokenAmount > 0) {
            uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128();
            fpGlobal.update(
                swapVTokenForVBase ? int256(vTokenAmount) : -int256(vTokenAmount), // when trader goes long, LP goes short
                state.liquidity,
                _blockTimestamp(),
                priceX128,
                vPool.twapSqrtPrice(timeHorizon).toPriceX128() // virtual pool twap price
            );

            sumFeeGlobalX128 += liquidityFees.mulDiv(FixedPoint128.Q128, state.liquidity);
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
    function zeroSwap() internal {
        uint256 priceX128 = oracle.getTwapSqrtPriceX96(timeHorizon).toPriceX128();
        fpGlobal.update(0, 1, _blockTimestamp(), priceX128, vPool.twapSqrtPrice(timeHorizon).toPriceX128());
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

    enum CalcFeeEnum {
        CALCULATE_ON_AMOUNT,
        CALCULATE_ON_SCALED
    }

    function _calculateFees(int256 amount, CalcFeeEnum calcFeeEnum)
        internal
        view
        returns (uint256 liquidityFees, uint256 protocolFees)
    {
        uint256 amountAbs = uint256(amount.abs());
        if (calcFeeEnum == CalcFeeEnum.CALCULATE_ON_SCALED) {
            // if we do not want to charge fees from amount, we scale it up so that
            // on charging fees on the scaled amount, we should get original amount
            amountAbs = (amountAbs * 1e6) / uint256(1e6 - liquidityFeePips - protocolFeePips);
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

    function _includeFees(
        uint256 amount,
        uint256 fees,
        IncludeFeeEnum includeFeeEnum
    ) internal pure returns (uint256 amountAfterFees) {
        if ((amount > 0) == (includeFeeEnum == IncludeFeeEnum.ADD_FEE)) {
            amountAfterFees = amount + fees;
        } else {
            amountAfterFees = amount - fees;
        }
    }
}
