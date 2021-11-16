//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VPoolFactory } from './VPoolFactory.sol';

contract ClearingHouse is VPoolFactory {
    constructor(
        address VBASE_ADDRESS,
        address UNISWAP_FACTORY_ADDRESS,
        uint24 DEFAULT_FEE_TIER,
        bytes32 POOL_BYTE_CODE_HASH
    ) VPoolFactory(VBASE_ADDRESS, UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH) {}
}
