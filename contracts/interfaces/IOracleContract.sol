//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracleContract {
    function getTwapSqrtPrice(uint32 twapDuration) external pure returns (uint160 sqrtPrice);
}
