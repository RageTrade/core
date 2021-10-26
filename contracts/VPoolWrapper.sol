//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolFactory.sol';

contract VPoolWrapper is IVPoolWrapper {
    uint16 public immutable override initialMarginRatio;
    uint16 public immutable override maintainanceMarginRatio;
    uint32 public immutable override timeHorizon;

    constructor() {
        (initialMarginRatio, maintainanceMarginRatio, timeHorizon) = IVPoolFactory(msg.sender).parameters();
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        override
        returns (
            uint256 sumA,
            uint256 sumBInside,
            uint256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        )
    {}
}
