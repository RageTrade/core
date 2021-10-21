//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Uint48L5ArrayLib {
    using Uint48L5ArrayLib for uint48[5];

    function include(uint48[5] storage array, uint48 element) internal {
        require(element != 0, 'Uint48L5ArrayLib:include:A');
        uint256 emptyIndex = 5; // max index is 4
        for (uint256 i; i < 5; i++) {
            if (array[i] == element) {
                return;
            }
            if (emptyIndex == 5 && array[i] == uint48(0)) {
                emptyIndex = i;
            }
        }

        require(emptyIndex != 5, 'Uint48L5ArrayLib:include:B');

        array[emptyIndex] = element;
    }

    function exclude(uint48[5] storage array, uint48 element) internal {
        require(element != 0, 'Uint48L5ArrayLib:exclude');

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
}
