//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracle {
    function getPrice(uint256 interval) external view returns (uint160);
}
