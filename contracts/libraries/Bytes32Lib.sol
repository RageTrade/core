// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Bytes32Lib {
    struct Bytes32 {
        bytes32 data;
    }

    // struct Bytes32 methods

    function copyToMemory(bytes32 data) internal pure returns (Bytes32 memory) {
        return Bytes32(data);
    }

    function pop(Bytes32 memory input, uint256 bits) internal pure returns (uint256 value) {
        (value, input.data) = pop(input.data, bits);
    }

    function popAddress(Bytes32 memory input) internal pure returns (address value) {
        uint256 temp;
        (temp, input.data) = pop(input.data, 160);
        assembly {
            value := temp
        }
    }

    function popUint16(Bytes32 memory input) internal pure returns (uint16 value) {
        uint256 temp;
        (temp, input.data) = pop(input.data, 16);
        value = uint16(temp);
    }

    function popUint32(Bytes32 memory input) internal pure returns (uint32 value) {
        uint256 temp;
        (temp, input.data) = pop(input.data, 32);
        value = uint32(temp);
    }

    function popBool(Bytes32 memory input) internal pure returns (bool value) {
        uint256 temp;
        (temp, input.data) = pop(input.data, 8);
        value = temp != 0;
    }

    function slice(
        Bytes32 memory input,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256 val) {
        return slice(input.data, start, end);
    }

    // primitive bytes32 methods

    function fromUint(uint256 input) internal pure returns (bytes32 output) {
        assembly {
            output := input
        }
    }

    function keccak256One(bytes32 input) internal pure returns (bytes32 result) {
        assembly {
            mstore(0, input)
            result := keccak256(0, 0x20)
        }
    }

    function keccak256Two(bytes32 input1, bytes32 input2) internal pure returns (bytes32 result) {
        assembly {
            mstore(0, input1)
            mstore(0x20, input2)
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
    ) internal pure returns (uint256 val) {
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

    function toAddress(bytes32 input) internal pure returns (address value) {
        uint256 temp;
        (temp, input) = pop(input, 160);
        assembly {
            value := temp
        }
    }

    function toUint16(bytes32 input) internal pure returns (uint16 value) {
        uint256 temp;
        (temp, input) = pop(input, 16);
        value = uint16(temp);
    }

    function toUint32(bytes32 input) internal pure returns (uint32 value) {
        uint256 temp;
        (temp, input) = pop(input, 32);
        value = uint32(temp);
    }

    function toBool(bytes32 input) internal pure returns (bool value) {
        uint256 temp;
        (temp, input) = pop(input, 8);
        value = temp != 0;
    }
}
