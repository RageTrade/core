//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
        for (uint256 i; i < 8; i++) {
            if (array[i] == element) {
                array[i] = 0;
            }
        }
    }
}
