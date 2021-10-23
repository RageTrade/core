//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Uint48Lib {
    function concat(int24 val1, int24 val2) internal pure returns (uint48 concatenated) {
        assembly {
            // concatenated := add(shl(24, val1), shr(232, shl(232, val2)))
            concatenated := add(shl(24, val1), and(val2, 0x000000ffffff))
        }
    }

    function unconcat(uint48 concatenated) internal pure returns (int24 val1, int24 val2) {
        assembly {
            val2 := concatenated
            val1 := shr(24, concatenated)
        }
    }
}
