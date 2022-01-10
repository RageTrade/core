//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Calldata {
    function calculateCostUnits(bytes calldata data) internal pure returns (uint256 cost) {
        unchecked {
            for (uint256 i; i < data.length; i++) {
                cost += data[i] == bytes1(0) ? 4 : 16;
            }
        }
    }
}
