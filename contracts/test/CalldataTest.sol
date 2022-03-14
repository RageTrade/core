// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Calldata } from '../libraries/Calldata.sol';

contract CalldataTest {
    function calculateCostUnits(bytes calldata data) external pure returns (uint256 cost) {
        return Calldata.calculateCostUnits(data);
    }
}
