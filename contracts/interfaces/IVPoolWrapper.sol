//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IVPoolWrapper {
    function timeHorizon() external view returns (uint32);

    function initialMarginRatio() external view returns (uint16);

    function maintainanceMarginRatio() external view returns (uint16);

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            uint256 sumA,
            uint256 sumBInside,
            uint256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        );
}
