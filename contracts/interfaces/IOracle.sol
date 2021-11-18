//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracle {
    function getTwapSqrtPriceX96(uint32 twapDuration) external view returns (uint160 sqrtPriceX96);
}
