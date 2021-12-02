//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { VTokenAddress } from '../libraries/VTokenLib.sol';

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
            uint256 uniswapFeeInside,
            uint256 extendedFeeInside
        );

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external returns (int256 vBaseAmount, int256 vTokenAmount);

    function getSumAX128() external view returns (int256);

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount);

    function collectAccruedProtocolFee() external returns (uint256 accruedProtocolFeeLast);

    function setOracle(address oracle_) external;
}
