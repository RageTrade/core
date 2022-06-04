// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { WordHelper } from '../libraries/WordHelper.sol';

contract WordHelperTest {
    function keccak256One(bytes32 input) public pure returns (bytes32 result) {
        return WordHelper.keccak256One(input);
    }

    function keccak256Two(bytes32 input1, bytes32 input2) public pure returns (bytes32 result) {
        return WordHelper.keccak256Two(input1, input2);
    }

    function slice(
        bytes32 input,
        uint256 start,
        uint256 end
    ) public pure returns (uint256 val) {
        return WordHelper.slice(input, start, end);
    }

    function offset(bytes32 key, uint256 offset_) public pure returns (bytes32) {
        return WordHelper.offset(key, offset_);
    }

    function pop(bytes32 input, uint256 bits) public pure returns (uint256 value, bytes32 inputUpdated) {
        return WordHelper.pop(input, bits);
    }

    function popAddress(bytes32 input) public pure returns (address value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popAddress(input);
    }

    function popUint16(bytes32 input) public pure returns (uint16 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint16(input);
    }

    function popUint32(bytes32 input) public pure returns (uint32 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint32(input);
    }

    function popBool(bytes32 input) public pure returns (bool value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popBool(input);
    }
}
