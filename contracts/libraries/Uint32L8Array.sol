//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Uint32L8ArrayLib {
    using Uint32L8ArrayLib for uint32[8];

    function include(uint32[8] storage array, uint32 element) internal {
        require(element != 0, 'Uint32L8ArrayLib:include:A');
        uint256 emptyIndex = 8; // max index is 7
        for (uint256 i; i < 8; i++) {
            if (array[i] == element) {
                return;
            }
            if (emptyIndex == 8 && array[i] == uint32(0)) {
                emptyIndex = i;
            }
        }

        require(emptyIndex != 8, 'Uint32L8ArrayLib:include:B');

        array[emptyIndex] = element;
    }

    function exclude(uint32[8] storage array, uint32 element) internal {
        require(element != 0, 'Uint32L8ArrayLib:exclude');

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

        if (elementIndex != 8) {
            if (i == elementIndex) {
                array[elementIndex] = 0;
            } else {
                // move last to element's place and empty lastIndex slot
                (array[elementIndex], array[i]) = (array[i], 0);
            }
        }
    }
}
