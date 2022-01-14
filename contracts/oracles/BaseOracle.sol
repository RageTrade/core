//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../interfaces/IOracle.sol';

contract BaseOracle is IOracle {
    function getTwapSqrtPriceX96(uint32) external pure returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = 1 << 96;
    }
}
