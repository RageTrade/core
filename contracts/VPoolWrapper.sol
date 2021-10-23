//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IvPoolWrapper.sol';

contract VPoolWrapper is IvPoolWrapper {
    uint32 public immutable override timeHorizon;
    uint16 public immutable override initialMarginRatio;
    uint16 public immutable override maintainanceMarginRatio;

    constructor(
        uint32 _timeHorizon,
        uint16 _initialMarginRatio,
        uint16 _maintainanceMarginRatio
    ) {
        timeHorizon = _timeHorizon;
        initialMarginRatio = _initialMarginRatio;
        maintainanceMarginRatio = _maintainanceMarginRatio;
    }
}
