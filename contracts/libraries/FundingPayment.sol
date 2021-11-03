//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from './FullMath.sol';

library FundingPayment {
    using FullMath for int256;

    int256 private constant PRECISION_FACTOR = 10**18;

    struct Info {
        int256 sumA;
        int256 sumB;
        int256 sumFp;
        uint48 timestampLast;
    }

    function update(
        Info storage global,
        int256 tokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal {
        int256 a = nextA(global.timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
        global.sumFp += a * global.sumB;
        global.sumA += a;
        global.sumB += tokenAmount.mulDiv(PRECISION_FACTOR, int256(liquidity));
        global.timestampLast = blockTimestamp;
    }

    function nextA(
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal pure returns (int256) {
        // FR * P * dt
        return
            ((realPriceX128 - virtualPriceX128).mulDiv(virtualPriceX128, realPriceX128).mulDiv(
                PRECISION_FACTOR,
                1 << 128
            ) * int48(blockTimestamp - timestampLast)) / 1 days;
    }

    function extrapolatedSumA(
        int256 sumA,
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal pure returns (int256) {
        return sumA + nextA(timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumFp(
        int256 sumA,
        int256 sumB,
        int256 sumFp,
        int256 sumALatest
    ) internal pure returns (int256) {
        return sumFp + sumB * (sumALatest - sumA);
    }

    function bill(int256 sumFp, uint256 liquidity) internal pure returns (int256) {
        return sumFp.mulDiv(int256(liquidity), PRECISION_FACTOR * PRECISION_FACTOR);
    }
}
