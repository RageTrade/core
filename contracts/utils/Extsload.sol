// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IExtsload } from '../interfaces/IExtsload.sol';

/// @notice Allows the contract to make it's state public
abstract contract Extsload is IExtsload {
    function extsload(uint256 slot) external view returns (uint256 val) {
        assembly {
            val := sload(slot)
        }
    }

    function extsload(uint256[] memory slots) external view returns (uint256[] memory) {
        assembly {
            let end := add(0x20, add(slots, mul(mload(slots), 0x20)))
            for {
                let pointer := add(slots, 32)
            } lt(pointer, end) {

            } {
                let value := sload(mload(pointer))
                mstore(pointer, value)
                pointer := add(pointer, 0x20)
            }
        }

        return slots;
    }
}
