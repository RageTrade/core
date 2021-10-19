//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Uint32L8Array {
    using Uint32L8Array for uint32[8];

    function get(uint32[8] memory array, uint8 index) internal pure returns (uint32) {
        return array[index];
    }

    function indexOf(uint32[8] memory array, uint32 element) internal pure returns (uint8) {
        for (uint8 i; i < 8; i++) {
            if (array[i] == element) {
                return i;
            }
        }
        return 255;
    }

    function exists(uint32[8] memory array, uint32 element) internal pure returns (bool) {
        return array.indexOf(element) != 255;
    }

    function include(uint32[8] memory array, uint32 element) internal pure {
        uint256 emptyIndex = 8; // max index is 7
        for (uint256 i; i < 8; i++) {
            if (array[i] == element) {
                return;
            }
            if (emptyIndex == 8 && array[i] == uint32(0)) {
                emptyIndex = i;
            }
        }

        require(emptyIndex != 8, 'limit of 8 vtokens exceeded, pls close positions to create new');

        array[emptyIndex] = element;
    }

    function exclude(uint32[8] memory array, uint32 element) internal pure {
        for (uint256 i; i < 8; i++) {
            if (array[i] == element) {
                array[i] = 0;
            }
        }
    }
}
