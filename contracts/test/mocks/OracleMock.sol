// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../../interfaces/IOracle.sol';
import { FullMath } from '../../libraries/FullMath.sol';

contract OracleMock is IOracle {
    uint160 _sqrtPrice;

    constructor() {
        setSqrtPrice(1 << 96);
    }

    function getTwapSqrtPrice(uint32) external view returns (uint160 sqrtPrice) {
        return _sqrtPrice;
    }

    function setSqrtPrice(uint160 sqrtPrice) public {
        _sqrtPrice = sqrtPrice;
    }

    function getTwapPriceX128(uint32) external view returns (uint256 sqrtPriceX128) {
        return FullMath.mulDiv(_sqrtPrice, _sqrtPrice, 1 << 64);
    }
}
