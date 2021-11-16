//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { console } from 'hardhat/console.sol';

contract UtilsTest {
    function convertAddressToUint160(address _add) external pure returns (uint160) {
        return (uint160(_add));
    }
}
