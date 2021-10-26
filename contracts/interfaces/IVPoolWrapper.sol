//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IVPoolWrapper {
    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        returns (
            uint256 sumA,
            uint256 sumBInside,
            uint256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        );
}
