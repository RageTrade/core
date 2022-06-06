// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';

import { ClearingHouseExtsload } from '../extsloads/ClearingHouseExtsload.sol';

contract ClearingHouseLens {
    using ClearingHouseExtsload for IClearingHouse;

    IClearingHouse public immutable clearingHouse;

    constructor(IClearingHouse _clearingHouse) {
        clearingHouse = _clearingHouse;
    }

    function getProtocolInfo()
        external
        view
        returns (
            IERC20 settlementToken,
            IVQuote vQuote,
            IClearingHouse.LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        return clearingHouse.getProtocolInfo();
    }

    function getVPool(uint32 poolId) external view returns (IUniswapV3Pool vPool) {
        return clearingHouse.getVPool(poolId);
    }

    function getPoolSettings(uint32 poolId) external view returns (IClearingHouse.PoolSettings memory settings) {
        return clearingHouse.getPoolSettings(poolId);
    }

    function getTwapDuration(uint32 poolId) external view returns (uint32 twapDuration) {
        return clearingHouse.getTwapDuration(poolId);
    }

    function getVPoolAndTwapDuration(uint32 poolId) external view returns (IUniswapV3Pool vPool, uint32 twapDuration) {
        return clearingHouse.getVPoolAndTwapDuration(poolId);
    }

    function isPoolIdAvailable(uint32 poolId) external view returns (bool) {
        return clearingHouse.isPoolIdAvailable(poolId);
    }

    function getCollateralInfo(uint32 collateralId) external view returns (IClearingHouse.Collateral memory) {
        return clearingHouse.getCollateralInfo(collateralId);
    }
}
