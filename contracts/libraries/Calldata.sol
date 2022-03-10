// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// @title Calldata functions
library Calldata {
    error CalldataLengthExceeded(uint256 length, uint256 limit);

    function limit(uint256 limit_) internal pure {
        if (msg.data.length > limit_) {
            revert CalldataLengthExceeded(msg.data.length, limit_);
        }
    }

    function calculateCostUnits(bytes calldata data) internal pure returns (uint256 cost) {
        unchecked {
            for (uint256 i; i < data.length; i++) {
                cost += data[i] == bytes1(0) ? 4 : 16;
            }
        }
    }
}
