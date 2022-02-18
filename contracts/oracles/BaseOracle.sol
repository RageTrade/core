//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../interfaces/IOracle.sol';

contract BaseOracle is IOracle {
    function getTwapPriceX128(
        uint32,
        uint8,
        uint8
    ) external pure returns (uint256 priceX128) {
        priceX128 = 1 << 128;
    }

    function getTwapSqrtPriceX96(
        uint32 twapDuration,
        uint8 tokenDecimals,
        uint8 baseDecimals
    ) external view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = 1 << 96;
    }
}
