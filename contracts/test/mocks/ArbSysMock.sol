// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IOracle } from '../../interfaces/IOracle.sol';

import { PriceMath } from '../../libraries/PriceMath.sol';

contract ArbSysMock {
    using PriceMath for uint256;
    using PriceMath for uint160;

    uint256 public arbBlockNumber;

    constructor() {
        setArbBlockNumber(0);
    }

    function setArbBlockNumber(uint256 _arbBlockNumber) public {
        arbBlockNumber = _arbBlockNumber;
    }
}
