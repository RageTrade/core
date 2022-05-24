// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { SignedMath } from './SignedMath.sol';

/// @title Signed full math functions
library SignedFullMath {
    using SafeCast for uint256;
    using SignedMath for int256;

    /// @notice uses full math on signed int and two unsigned ints
    /// @param a: signed int
    /// @param b: unsigned int to be multiplied by
    /// @param denominator: unsigned int to be divided by
    /// @return result of a * b / denominator
    function mulDiv(
        int256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (int256 result) {
        result = FullMath.mulDiv(a < 0 ? uint256(-1 * a) : uint256(a), b, denominator).toInt256();
        if (a < 0) {
            result = -result;
        }
    }

    /// @notice uses full math on three signed ints
    /// @param a: signed int
    /// @param b: signed int to be multiplied by
    /// @param denominator: signed int to be divided by
    /// @return result of a * b / denominator
    function mulDiv(
        int256 a,
        int256 b,
        int256 denominator
    ) internal pure returns (int256 result) {
        bool resultPositive = true;
        uint256 _a;
        uint256 _b;
        uint256 _denominator;

        (_a, resultPositive) = a.extractSign(resultPositive);
        (_b, resultPositive) = b.extractSign(resultPositive);
        (_denominator, resultPositive) = denominator.extractSign(resultPositive);

        result = FullMath.mulDiv(_a, _b, _denominator).toInt256();
        if (!resultPositive) {
            result = -result;
        }
    }

    /// @notice rounds down towards negative infinity
    /// @dev in Solidity -3/2 is -1. But this method result is -2
    /// @param a: signed int
    /// @param b: unsigned int to be multiplied by
    /// @param denominator: unsigned int to be divided by
    /// @return result of a * b / denominator rounded towards negative infinity
    function mulDivRoundingDown(
        int256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (int256 result) {
        result = mulDiv(a, b, denominator);
        if (result < 0 && _hasRemainder(a.absUint(), b, denominator)) {
            result += -1;
        }
    }

    /// @notice rounds down towards negative infinity
    /// @dev in Solidity -3/2 is -1. But this method result is -2
    /// @param a: signed int
    /// @param b: signed int to be multiplied by
    /// @param denominator: signed int to be divided by
    /// @return result of a * b / denominator rounded towards negative infinity
    function mulDivRoundingDown(
        int256 a,
        int256 b,
        int256 denominator
    ) internal pure returns (int256 result) {
        result = mulDiv(a, b, denominator);
        if (result < 0 && _hasRemainder(a.absUint(), b.absUint(), denominator.absUint())) {
            result += -1;
        }
    }

    /// @notice checks if full multiplication of a & b would have a remainder if divided by denominator
    /// @param a: multiplicand
    /// @param b: multiplier
    /// @param denominator: divisor
    /// @return hasRemainder true if there is a remainder, false otherwise
    function _hasRemainder(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) private pure returns (bool hasRemainder) {
        assembly {
            let remainder := mulmod(a, b, denominator)
            if gt(remainder, 0) {
                hasRemainder := 1
            }
        }
    }
}
