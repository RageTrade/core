//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FundingPayment } from '../libraries/FundingPayment.sol';

contract FundingPaymentTest {
    using FundingPayment for FundingPayment.Info;

    FundingPayment.Info public fpGlobal;

    function update(
        int256 tokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) public {
        return fpGlobal.update(tokenAmount, liquidity, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function nextA(
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) public pure returns (int256) {
        return FundingPayment.nextA(timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumA(
        int256 sumA,
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) public pure returns (int256) {
        return FundingPayment.extrapolatedSumA(sumA, timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumFp(
        int256 sumA,
        int256 sumB,
        int256 sumFp,
        int256 sumALatest
    ) public pure returns (int256) {
        return FundingPayment.extrapolatedSumFp(sumA, sumB, sumFp, sumALatest);
    }

    function bill(int256 sumFp, uint256 liquidity) internal pure returns (int256) {
        return FundingPayment.bill(sumFp, liquidity);
    }
}
