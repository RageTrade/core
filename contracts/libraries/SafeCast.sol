// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library SafeCast {
    error SafeCaseInt128Overflow(uint128 value);

    function toInt128(uint128 y) internal pure returns (int128 z) {
        unchecked {
            if (y >= 2**127) revert SafeCaseInt128Overflow(y);
            z = int128(y);
        }
    }

    error SafeCastInt256Overflow(uint256 value);

    function toInt256(uint256 y) internal pure returns (int256 z) {
        unchecked {
            if (y >= 2**255) revert SafeCastInt256Overflow(y);
            z = int256(y);
        }
    }
}
