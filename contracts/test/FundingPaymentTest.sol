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

    function nextAX128(
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) public pure returns (int256) {
        return FundingPayment.nextAX128(timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumAX128(
        int256 sumA,
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) public pure returns (int256) {
        return
            FundingPayment.extrapolatedSumAX128(sumA, timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumFpX128(
        int256 sumAX128,
        int256 sumBX128,
        int256 sumFpX128,
        int256 sumALatestX128
    ) public pure returns (int256) {
        return FundingPayment.extrapolatedSumFpX128(sumAX128, sumBX128, sumFpX128, sumALatestX128);
    }

    function bill(int256 sumFpX128, uint256 liquidity) internal pure returns (int256) {
        return FundingPayment.bill(sumFpX128, liquidity);
    }
}
