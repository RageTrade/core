//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

/// @notice Allows the contract to make it's state public
abstract contract Extsload {
    function extsload(bytes32 slot) external view returns (bytes32 val) {
        assembly {
            val := sload(slot)
        }
    }

    function extsload(bytes32[] memory slots) external view returns (bytes32[] memory) {
        uint256 len = slots.length;

        assembly {
            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 1)
            } {
                let offset := mul(i, 0x20)
                let value := sload(mload(add(slots, offset)))
                mstore(add(slots, offset), value)
            }
        }

        return slots;
    }
}
