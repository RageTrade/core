//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VPoolWrapper } from '../../VPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapperMock2 is VPoolWrapper {
    uint48 public blockTimestamp;

    constructor() {
        blockTimestamp = uint48(block.timestamp);
    }

    function _blockTimestamp() internal view override returns (uint48) {
        // constructor of VPoolWrapper runs first, there _blockTimestamp() returns zero
        if (blockTimestamp == 0) return uint48(block.timestamp);
        else return blockTimestamp;
    }

    function increaseTimestamp(uint48 secs) external {
        blockTimestamp += secs;
    }

    function swapInternal(
        bool swapVTokenForVBase, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (int256 vTokenIn, int256 vBaseIn) {
        return _swap(swapVTokenForVBase, amountSpecified, sqrtPriceLimitX96);
    }
}
