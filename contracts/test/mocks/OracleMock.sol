// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../../interfaces/IOracle.sol';

contract OracleMock is IOracle {
    uint160 _sqrtPriceX96;

    constructor() {
        setSqrtPrice(1 << 96);
    }

    function getTwapSqrtPriceX96(uint32) external view returns (uint160 sqrtPriceX96) {
        return _sqrtPriceX96;
    }

    function setSqrtPrice(uint160 sqrtPriceX96) public {
        _sqrtPriceX96 = sqrtPriceX96;
    }
}
