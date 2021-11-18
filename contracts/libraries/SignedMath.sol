//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

int256 constant ONE = 1;

library SignedMath {
    function abs(int256 value) internal pure returns (int256) {
        return value > 0 ? value : -value;
    }

    function sign(int256 value) internal pure returns (int256) {
        return value > 0 ? ONE : -ONE;
    }
}
