//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from './FullMath.sol';
import { FixedPoint128 } from './uniswap/FixedPoint128.sol';

library FundingPayment {
    using FullMath for int256;

    struct Info {
        // FR * P * dt
        int256 sumAX128;
        // trade token amount / liqidity
        int256 sumBX128;
        // sum(a * sumB)
        int256 sumFpX128;
        // time when state was last updated
        uint48 timestampLast;
    }

    function update(
        Info storage info,
        int256 tokenAmount,
        uint256 liquidity,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal {
        int256 a = nextAX128(info.timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
        info.sumFpX128 += a.mulDiv(info.sumBX128, int256(FixedPoint128.Q128));
        info.sumAX128 += a;
        info.sumBX128 += tokenAmount.mulDiv(int256(FixedPoint128.Q128), int256(liquidity));
        info.timestampLast = blockTimestamp;
    }

    function nextAX128(
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal pure returns (int256 aX128) {
        return
            (realPriceX128 - virtualPriceX128).mulDiv(virtualPriceX128, realPriceX128).mulDiv(
                int48(blockTimestamp - timestampLast),
                1 days
            );
    }

    function extrapolatedSumAX128(
        int256 sumAX128,
        uint48 timestampLast,
        uint48 blockTimestamp,
        int256 realPriceX128,
        int256 virtualPriceX128
    ) internal pure returns (int256) {
        return sumAX128 + nextAX128(timestampLast, blockTimestamp, realPriceX128, virtualPriceX128);
    }

    function extrapolatedSumFpX128(
        int256 sumAX128,
        int256 sumBX128,
        int256 sumFpX128,
        int256 sumAGlobalX128
    ) internal pure returns (int256) {
        return sumFpX128 + sumBX128.mulDiv(sumAGlobalX128 - sumAX128, int256(FixedPoint128.Q128));
    }

    function bill(int256 sumFpX128, uint256 liquidity) internal pure returns (int256) {
        return sumFpX128.mulDiv(int256(liquidity), int256(FixedPoint128.Q128)); // TODO: refactor FullMath signed mulDiv
    }
}
