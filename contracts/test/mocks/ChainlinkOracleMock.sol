// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IChainlinkOracle } from '../../interfaces/IChainlinkOracle.sol';

contract ChainlinkOracleMock is IChainlinkOracle {
    uint256 priceX128;

    constructor() {
        setPriceX128(1 << 128);
    }

    function getTwapPriceX128(
        uint32,
        uint8,
        uint8
    ) external view returns (uint256) {
        return priceX128;
    }

    function setPriceX128(uint160 _priceX128) public {
        priceX128 = _priceX128;
    }
}
