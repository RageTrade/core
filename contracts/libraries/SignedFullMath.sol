// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

library SignedFullMath {
    function mulDiv(
        int256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (int256 result) {
        result = int256(FullMath.mulDiv(a < 0 ? uint256(-1 * a) : uint256(a), b, denominator));
        if (a < 0) {
            result *= -1;
        }
    }

    function mulDiv(
        int256 a,
        int256 b,
        int256 denominator
    ) internal pure returns (int256 result) {
        bool resultPositive = true;
        uint256 _a;
        uint256 _b;
        uint256 _denominator;
        if (a < 0) {
            resultPositive = !resultPositive;
            _a = uint256(-1 * a);
        } else {
            _a = uint256(a);
        }
        if (b < 0) {
            resultPositive = !resultPositive;
            _b = uint256(-1 * b);
        } else {
            _b = uint256(b);
        }
        if (denominator < 0) {
            resultPositive = !resultPositive;
            _denominator = uint256(-1 * denominator);
        } else {
            _denominator = uint256(denominator);
        }
        result = int256(FullMath.mulDiv(_a, _b, _denominator));
        if (!resultPositive) {
            result *= -1;
        }
    }
}
