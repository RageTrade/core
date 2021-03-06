// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

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
    ) public pure returns (bytes32 val) {
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

    function popUint8(bytes32 input) public pure returns (uint8 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint8(input);
    }

    function popUint16(bytes32 input) public pure returns (uint16 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint16(input);
    }

    function popUint32(bytes32 input) public pure returns (uint32 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint32(input);
    }

    function popUint64(bytes32 input) public pure returns (uint64 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint64(input);
    }

    function popUint128(bytes32 input) public pure returns (uint128 value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popUint128(input);
    }

    function popBool(bytes32 input) public pure returns (bool value, bytes32 inputUpdated) {
        (value, inputUpdated) = WordHelper.popBool(input);
    }

    function convertToUint32Array(bytes32 active) external pure returns (uint32[] memory activeArr) {
        return WordHelper.convertToUint32Array(active);
    }

    function convertToTickRangeArray(bytes32 active)
        external
        view
        returns (IClearingHouseStructures.TickRange[] memory activeArr)
    {
        return WordHelper.convertToTickRangeArray(active);
    }
}
