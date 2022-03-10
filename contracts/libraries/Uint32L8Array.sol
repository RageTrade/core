// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// @title Uint32 length 8 array functions
/// @dev Fits in one storage slot
library Uint32L8ArrayLib {
    using Uint32L8ArrayLib for uint32[8];

    error U32L8_IllegalElement(uint32 element);
    error U32L8_NoSpaceLeftToInsert(uint32 element);

    function include(uint32[8] storage array, uint32 element) internal {
        if (element == 0) {
            revert U32L8_IllegalElement(0);
        }

        uint256 emptyIndex = 8; // max index is 7
        for (uint256 i; i < 8; i++) {
            if (array[i] == element) {
                return;
            }
            if (emptyIndex == 8 && array[i] == uint32(0)) {
                emptyIndex = i;
                break;
            }
        }

        if (emptyIndex == 8) {
            revert U32L8_NoSpaceLeftToInsert(element);
        }

        array[emptyIndex] = element;
    }

    function exclude(uint32[8] storage array, uint32 element) internal {
        if (element == 0) {
            revert U32L8_IllegalElement(0);
        }

        uint256 elementIndex = 8;
        uint256 i;

        for (; i < 8; i++) {
            if (array[i] == element) {
                elementIndex = i;
            }
            if (array[i] == 0) {
                i = i > 0 ? i - 1 : 0; // last non-zero element
                break;
            }
        }

        i = i == 8 ? 7 : i;

        if (elementIndex != 8) {
            if (i == elementIndex) {
                array[elementIndex] = 0;
            } else {
                // move last to element's place and empty lastIndex slot
                (array[elementIndex], array[i]) = (array[i], 0);
            }
        }
    }

    function indexOf(uint32[8] storage array, uint32 element) internal view returns (uint8) {
        for (uint8 i; i < 8; i++) {
            if (array[i] == element) {
                return i;
            }
        }
        return 255;
    }

    function exists(uint32[8] storage array, uint32 element) internal view returns (bool) {
        return array.indexOf(element) != 255;
    }

    function numberOfNonZeroElements(uint32[8] storage array) internal view returns (uint256) {
        for (uint8 i; i < 8; i++) {
            if (array[i] == 0) {
                return i;
            }
        }
        return 8;
    }
}
