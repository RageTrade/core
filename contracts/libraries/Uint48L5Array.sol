//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Uint48L5ArrayLib {
    using Uint48L5ArrayLib for uint48[5];

    error U48L5_IllegalElement(uint48 element);
    error U48L5_NoSpaceLeftToInsert(uint48 element);

    function include(uint48[5] storage array, uint48 element) internal {
        if (element == 0) {
            revert U48L5_IllegalElement(0);
        }
        uint256 emptyIndex = 5; // max index is 4
        for (uint256 i; i < 5; i++) {
            if (array[i] == element) {
                return;
            }
            if (emptyIndex == 5 && array[i] == uint48(0)) {
                emptyIndex = i;
            }
        }

        if (emptyIndex == 5) {
            revert U48L5_NoSpaceLeftToInsert(element);
        }

        array[emptyIndex] = element;
    }

    function exclude(uint48[5] storage array, uint48 element) internal {
        if (element == 0) {
            revert U48L5_IllegalElement(0);
        }

        uint256 elementIndex = 5;
        uint256 i;

        for (; i < 5; i++) {
            if (array[i] == element) {
                elementIndex = i;
            }
            if (array[i] == 0) {
                i = i > 0 ? i - 1 : 0; // last non-zero element
                break;
            }
        }

        if (elementIndex != 5) {
            if (i == elementIndex) {
                array[elementIndex] = 0;
            } else {
                // move last to element's place and empty lastIndex slot
                (array[elementIndex], array[i]) = (array[i], 0);
            }
        }
    }

    function indexOf(uint48[5] storage array, uint48 element) internal view returns (uint8) {
        for (uint8 i; i < 5; i++) {
            if (array[i] == element) {
                return i;
            }
        }
        return 255;
    }

    function exists(uint48[5] storage array, uint48 element) internal view returns (bool) {
        return array.indexOf(element) != 255;
    }

    function numberOfNonZeroElements(uint48[5] storage array) internal view returns (uint256) {
        for (uint8 i; i < 5; i++) {
            if (array[i] == 0) {
                return i;
            }
        }
        return 5;
    }
}
