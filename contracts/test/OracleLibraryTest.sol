//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Oracle } from '../libraries/Oracle.sol';

contract OracleTest {
    using Oracle for address;

    function checkPrice() external pure {
        // TODO add tests
        // assert(address(1).getPrice() == 0);
    }
}
