// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Bytes32Lib } from '../libraries/Bytes32Lib.sol';

contract Bytes32LibTest {
    function keccak256One(bytes32 input) public pure returns (bytes32 result) {
        return Bytes32Lib.keccak256One(input);
    }

    function keccak256Two(bytes32 input1, bytes32 input2) public pure returns (bytes32 result) {
        return Bytes32Lib.keccak256Two(input1, input2);
    }

    function slice(
        bytes32 input,
        uint256 start,
        uint256 end
    ) public pure returns (uint256 val) {
        return Bytes32Lib.slice(input, start, end);
    }

    function offset(bytes32 key, uint256 offset_) public pure returns (bytes32) {
        return Bytes32Lib.offset(key, offset_);
    }

    function pop(bytes32 input, uint256 bits) public pure returns (uint256 value, bytes32 inputUpdated) {
        return Bytes32Lib.pop(input, bits);
    }
}
