// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library WordHelper {
    struct Word {
        bytes32 data;
    }

    // struct Word methods

    function copyToMemory(bytes32 data) internal pure returns (Word memory) {
        return Word(data);
    }

    function pop(Word memory input, uint256 bits) internal pure returns (uint256 value) {
        (value, input.data) = pop(input.data, bits);
    }

    function popAddress(Word memory input) internal pure returns (address value) {
        (value, input.data) = popAddress(input.data);
    }

    function popUint16(Word memory input) internal pure returns (uint16 value) {
        (value, input.data) = popUint16(input.data);
    }

    function popUint32(Word memory input) internal pure returns (uint32 value) {
        (value, input.data) = popUint32(input.data);
    }

    function popUint64(Word memory input) internal pure returns (uint64 value) {
        (value, input.data) = popUint64(input.data);
    }

    function popUint128(Word memory input) internal pure returns (uint128 value) {
        (value, input.data) = popUint128(input.data);
    }

    function popBool(Word memory input) internal pure returns (bool value) {
        (value, input.data) = popBool(input.data);
    }

    function slice(
        Word memory input,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes32 val) {
        return slice(input.data, start, end);
    }

    // primitive uint256 methods

    function fromUint(uint256 input) internal pure returns (bytes32 output) {
        assembly {
            output := input
        }
    }

    // primitive bytes32 methods

    function keccak256One(bytes32 input) internal pure returns (bytes32 result) {
        assembly {
            mstore(0, input)
            result := keccak256(0, 0x20)
        }
    }

    function keccak256Two(bytes32 paddedKey, bytes32 mappingSlot) internal pure returns (bytes32 result) {
        assembly {
            mstore(0, paddedKey)
            mstore(0x20, mappingSlot)
            result := keccak256(0, 0x40)
        }
    }

    function offset(bytes32 key, uint256 offset_) internal pure returns (bytes32) {
        assembly {
            key := add(key, offset_)
        }
        return key;
    }

    function slice(
        bytes32 input,
        uint256 start,
        uint256 end
    ) internal pure returns (bytes32 val) {
        assembly {
            val := shl(start, input)
            val := shr(add(start, sub(256, end)), val)
        }
    }

    /// @notice pops bits from the right side of the input
    /// @dev E.g. input = 0x0102030405060708091011121314151617181920212223242526272829303132
    ///          input.pop(16) -> 0x3132
    ///          input.pop(16) -> 0x2930
    ///          input -> 0x0000000001020304050607080910111213141516171819202122232425262728
    /// @dev this does not throw on underflow, value returned would be zero
    /// @param input the input bytes
    /// @param bits the number of bits to pop
    /// @return value of the popped bits
    /// @return inputUpdated the input bytes shifted right by bits
    function pop(bytes32 input, uint256 bits) internal pure returns (uint256 value, bytes32 inputUpdated) {
        assembly {
            let shift := sub(256, bits)
            value := shr(shift, shl(shift, input))
            inputUpdated := shr(bits, input)
        }
    }

    function popAddress(bytes32 input) internal pure returns (address value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 160);
        assembly {
            value := temp
        }
    }

    function popUint16(bytes32 input) internal pure returns (uint16 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 16);
        value = uint16(temp);
    }

    function popUint32(bytes32 input) internal pure returns (uint32 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 32);
        value = uint32(temp);
    }

    function popUint64(bytes32 input) internal pure returns (uint64 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 64);
        value = uint64(temp);
    }

    function popUint128(bytes32 input) internal pure returns (uint128 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 128);
        value = uint128(temp);
    }

    function popBool(bytes32 input) internal pure returns (bool value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = pop(input, 8);
        value = temp != 0;
    }

    function toAddress(bytes32 input) internal pure returns (address value) {
        (value, ) = popAddress(input);
    }

    function toUint16(bytes32 input) internal pure returns (uint16 value) {
        (value, ) = popUint16(input);
    }

    function toUint32(bytes32 input) internal pure returns (uint32 value) {
        (value, ) = popUint32(input);
    }

    function toUint64(bytes32 input) internal pure returns (uint64 value) {
        (value, ) = popUint64(input);
    }

    function toUint128(bytes32 input) internal pure returns (uint128 value) {
        (value, ) = popUint128(input);
    }

    function toUint256(bytes32 input) internal pure returns (uint256 value) {
        assembly {
            value := input
        }
    }

    function toBool(bytes32 input) internal pure returns (bool value) {
        (value, ) = popBool(input);
    }
}
