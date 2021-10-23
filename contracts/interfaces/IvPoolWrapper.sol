//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IvPoolWrapper {
    function timeHorizon() external view returns (uint32);

    function initialMarginRatio() external view returns (uint16);

    function maintainanceMarginRatio() external view returns (uint16);
}
