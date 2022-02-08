// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../../interfaces/IOracle.sol';

contract OracleMock is IOracle {
    uint160 _sqrtPriceX96;
    uint256 _priceX128;

    constructor() {
        setSqrtPrice(1 << 96);
        setPrice(1 << 128);
    }

    function getTwapSqrtPriceX96(uint32) external view returns (uint160 sqrtPriceX96) {
        return _sqrtPriceX96;
    }

    function getTwapPriceX128(uint32) external view returns (uint256 priceX128) {
        return _priceX128;
    }

    function setSqrtPrice(uint160 sqrtPriceX96) public {
        _sqrtPriceX96 = sqrtPriceX96;
    }

    function setPrice(uint256 priceX128) public {
        _priceX128 = priceX128;
    }
}
