//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Oracle } from '../libraries/Oracle.sol';

contract OracleTest {
    using Oracle for address;

    function checkPrice() external pure {
        assert(address(1).getPrice() == 0);
    }
}
