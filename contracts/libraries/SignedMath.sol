// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

int256 constant ONE = 1;

/// @title Signed math functions
library SignedMath {
    /// @notice gives the absolute value of a signed int
    /// @param value signed int
    /// @return absolute value of signed int
    function abs(int256 value) internal pure returns (int256) {
        return value > 0 ? value : -value;
    }

    /// @notice gives the absolute value of a signed int
    /// @param value signed int
    /// @return absolute value of signed int as unsigned int
    function absUint(int256 value) internal pure returns (uint256) {
        return uint256(abs(value));
    }

    /// @notice gives the sign of a signed int
    /// @param value signed int
    /// @return -1 if negative, 1 if non-negative
    function sign(int256 value) internal pure returns (int256) {
        return value >= 0 ? ONE : -ONE;
    }

    /// @notice converts a signed integer into an unsigned integer and inverts positive bool if negative
    /// @param a signed int
    /// @param positive initial value of positive bool
    /// @return _a absolute value of int provided
    /// @return bool xor of the positive boolean and sign of the provided int
    function extractSign(int256 a, bool positive) internal pure returns (uint256 _a, bool) {
        if (a < 0) {
            positive = !positive;
            _a = uint256(-a);
        } else {
            _a = uint256(a);
        }
        return (_a, positive);
    }

    /// @notice extracts the sign of a signed int
    /// @param a signed int
    /// @return _a unsigned int
    /// @return bool sign of the provided int
    function extractSign(int256 a) internal pure returns (uint256 _a, bool) {
        return extractSign(a, true);
    }

    /// @notice returns the max of two int256 numbers
    /// @param a first number
    /// @param b second number
    /// @return c = max of a and b
    function max(int256 a, int256 b) internal pure returns (int256 c) {
        if (a > b) c = a;
        else c = b;
    }
}
