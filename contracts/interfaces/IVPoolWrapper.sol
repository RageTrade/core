//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IVPoolWrapper {
    function timeHorizon() external view returns (uint32);

    function initialMarginRatio() external view returns (uint16);

    function maintainanceMarginRatio() external view returns (uint16);

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int256 sumA,
            int256 sumBInside,
            int256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        );

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity
    ) external returns (int256 vBaseAmount, int256 vTokenAmount);

    function getExtrapolatedSumA() external pure returns (int256);
}
