//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SignedMath } from './SignedMath.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { console } from 'hardhat/console.sol';

library SwapMath {
    using SignedMath for int256;

    /// @dev This method mutates the data pointed by swapValues
    function beforeSwap(
        bool exactIn,
        bool swapVTokenForVBase,
        uint24 uniswapFeePips,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        IClearingHouseStructures.SwapValues memory swapValues
    ) internal pure {
        // inflate or deinfate to undo uniswap fees if necessary, and account for our fees
        if (exactIn) {
            if (swapVTokenForVBase) {
                // CASE: exactIn vToken
                // fee: not now, will collect fee in vBase after swap
                // inflate: for undoing the uniswap fees
                swapValues.amountSpecified = inflate(swapValues.amountSpecified, uniswapFeePips);
            } else {
                // CASE: exactIn vBase
                // fee: remove fee and do smaller swap, so trader gets less vTokens
                // here, amountSpecified == swap amount + fee
                (swapValues.liquidityFees, swapValues.protocolFees) = calculateFees(
                    swapValues.amountSpecified,
                    AmountTypeEnum.VBASE_AMOUNT_PLUS_FEES,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapValues.amountSpecified = includeFees(
                    swapValues.amountSpecified,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
                // inflate: uniswap will collect fee so inflate to undo it
                swapValues.amountSpecified = inflate(swapValues.amountSpecified, uniswapFeePips);
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
                (swapValues.liquidityFees, swapValues.protocolFees) = calculateFees(
                    swapValues.amountSpecified,
                    AmountTypeEnum.VBASE_AMOUNT_MINUS_FEES,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapValues.amountSpecified = includeFees(
                    swapValues.amountSpecified,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            }
        }
    }

    /// @dev This method mutates the data pointed by swapValues
    function afterSwap(
        bool exactIn,
        bool swapVTokenForVBase,
        uint24 uniswapFeePips,
        uint24 liquidityFeePips,
        uint24 protocolFeePips,
        IClearingHouseStructures.SwapValues memory swapValues
    ) internal pure {
        // swap is done so now adjusting vTokenIn and vBaseIn amounts to remove uniswap fees and add our fees
        if (exactIn) {
            if (swapVTokenForVBase) {
                // CASE: exactIn vToken
                // deinflate: vToken amount was inflated so that uniswap can collect fee
                swapValues.vTokenIn = deinflate(swapValues.vTokenIn, uniswapFeePips);

                // fee: collect the fee, give less vBase to trader
                // here, vBaseIn == swap amount
                (swapValues.liquidityFees, swapValues.protocolFees) = calculateFees(
                    swapValues.vBaseIn,
                    AmountTypeEnum.ZERO_FEE_VBASE_AMOUNT,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapValues.vBaseIn = includeFees(
                    swapValues.vBaseIn,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
            } else {
                // CASE: exactIn vBase
                // deinflate: vBase amount was inflated, hence need to deinflate for generating final statement
                swapValues.vBaseIn = deinflate(swapValues.vBaseIn, uniswapFeePips);
                // fee: fee is already removed before swap, lets include it to the final bill, so that trader pays for it
                swapValues.vBaseIn = includeFees(
                    swapValues.vBaseIn,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            }
        } else {
            if (!swapVTokenForVBase) {
                // CASE: exactOut vToken
                // deinflate: uniswap want to collect fee in vBase and hence ask more, so need to deinflate it
                swapValues.vBaseIn = deinflate(swapValues.vBaseIn, uniswapFeePips);
                // fee: collecting fees in vBase
                // here, vBaseIn == swap amount
                (swapValues.liquidityFees, swapValues.protocolFees) = calculateFees(
                    swapValues.vBaseIn,
                    AmountTypeEnum.ZERO_FEE_VBASE_AMOUNT,
                    liquidityFeePips,
                    protocolFeePips
                );
                swapValues.vBaseIn = includeFees(
                    swapValues.vBaseIn,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.ADD_FEE
                );
            } else {
                // CASE: exactOut vBase
                // deinflate: uniswap want to collect fee in vToken and hence ask more, so need to deinflate it
                swapValues.vTokenIn = deinflate(swapValues.vTokenIn, uniswapFeePips);
                // fee: already calculated before, subtract now
                swapValues.vBaseIn = includeFees(
                    swapValues.vBaseIn,
                    swapValues.liquidityFees + swapValues.protocolFees,
                    IncludeFeeEnum.SUBTRACT_FEE
                );
            }
        }
    }

    function inflate(int256 amount, uint24 uniswapFeePips) internal pure returns (int256 inflated) {
        int256 fees = (amount * int256(uint256(uniswapFeePips))) / int24(1e6 - uniswapFeePips) + 1; // round up
        inflated = amount + fees;
    }

    function deinflate(int256 inflated, uint24 uniswapFeePips) internal pure returns (int256 amount) {
        amount = (inflated * int24(1e6 - uniswapFeePips)) / 1e6;
    }

    enum AmountTypeEnum {
        ZERO_FEE_VBASE_AMOUNT,
        VBASE_AMOUNT_MINUS_FEES,
        VBASE_AMOUNT_PLUS_FEES
    }

    function calculateFees(
        int256 amount,
        AmountTypeEnum amountTypeEnum,
        uint24 liquidityFeePips,
        uint24 protocolFeePips
    ) internal pure returns (uint256 liquidityFees, uint256 protocolFees) {
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

    function includeFees(
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
