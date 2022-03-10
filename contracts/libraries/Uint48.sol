// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// @title Uint48 concating functions
library Uint48Lib {
    /// @notice Packs two int24 values into uint48
    /// @dev Used for concating two ticks into 48 bits value
    function concat(int24 val1, int24 val2) internal pure returns (uint48 concatenated) {
        assembly {
            concatenated := add(shl(24, val1), and(val2, 0x000000ffffff))
        }
    }

    /// @notice Unpacks uint48 into two int24 values
    function unconcat(uint48 concatenated) internal pure returns (int24 val1, int24 val2) {
        assembly {
            val2 := concatenated
            val1 := shr(24, concatenated)
        }
    }
}
