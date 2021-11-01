//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolFactory.sol';

contract VPoolWrapper is IVPoolWrapper {
    uint16 public immutable initialMarginRatio;
    uint16 public immutable maintainanceMarginRatio;
    uint32 public immutable timeHorizon;

    constructor() {
        (initialMarginRatio, maintainanceMarginRatio, timeHorizon) = IVPoolFactory(msg.sender).parameters();
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int256 sumA,
            int256 sumBInside,
            int256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        )
    {}

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity
    ) external returns (int256 vBaseAmount, int256 vTokenAmount) {}

    function getExtrapolatedSumA() external pure returns (uint256) {
        return 0;
    }
}
