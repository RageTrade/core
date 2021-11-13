//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from '../libraries/FullMath.sol';

import { console } from 'hardhat/console.sol';

contract FullMathTest {
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256 result) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function mulDiv(
        int256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (int256 result) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function mulDiv(
        int256 a,
        int256 b,
        int256 denominator
    ) public pure returns (int256 result) {
        return FullMath.mulDiv(a, b, denominator);
    }

    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) public pure returns (uint256 result) {
        return FullMath.mulDivRoundingUp(a, b, denominator);
    }
}
