//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IvPoolWrapper.sol';
import './interfaces/IvPoolFactory.sol';

contract VPoolWrapper is IvPoolWrapper {
    uint16 public immutable override initialMarginRatio;
    uint16 public immutable override maintainanceMarginRatio;
    uint32 public immutable override timeHorizon;

    constructor() {
        (initialMarginRatio, maintainanceMarginRatio, timeHorizon) = IvPoolFactory(msg.sender).parameters();
    }
}
