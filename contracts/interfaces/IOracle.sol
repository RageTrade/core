//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracle {
    function getTwapSqrtPrice(uint32 twapDuration) external view returns (uint160 sqrtPrice);

    function getTwapPriceX128(uint32 twapDuration) external view returns (uint256 sqrtPriceX128);
}
