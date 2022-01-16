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
        assembly {
            let end := add(0x20, add(slots, mul(mload(slots), 0x20)))
            for {
                let pointer := slots
            } lt(pointer, end) {

            } {
                pointer := add(pointer, 0x20)
                let value := sload(mload(pointer))
                mstore(pointer, value)
            }
        }

        return slots;
    }
}
