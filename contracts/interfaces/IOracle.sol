//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracle {
    // TODO change to X128 instead of X96
    function getTwapSqrtPriceX96(uint32 twapDuration) external view returns (uint160 sqrtPriceX96);

    function getTwapPriceX128(uint32 twapDuration) external view returns (uint256 priceX128);
}
