//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { VTokenAddress } from '../libraries/VTokenLib.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

interface IVPoolWrapper {
    event Swap(int256 vTokenIn, int256 vBaseIn, uint256 liquidityFees, uint256 protocolFees);

    function timeHorizon() external view returns (uint32);

    function vPool() external view returns (IUniswapV3Pool);

    function initialMarginRatio() external view returns (uint16);

    function maintainanceMarginRatio() external view returns (uint16);

    function whitelisted() external view returns (bool);

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int256 sumAX128,
            int256 sumBInsideX128,
            int256 sumFpInsideX128,
            uint256 sumFeeInsideX128
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
