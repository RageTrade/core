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

    function getPoolInfo(uint32 poolId) external view returns (IClearingHouse.Pool memory pool) {
        return clearingHouse.getPoolInfo(poolId);
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

    function getAccountInfo(uint256 accountId)
        external
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            uint32[] memory activeCollateralIds,
            uint32[] memory activePoolIds
        )
    {
        return clearingHouse.getAccountInfo(accountId);
    }

    function getAccountCollateralInfo(uint256 accountId, uint32 collateralId)
        external
        view
        returns (IERC20 collateral, uint256 balance)
    {
        return clearingHouse.getAccountCollateralInfo(accountId, collateralId);
    }

    function getAccountCollateralBalance(uint256 accountId, uint32 collateralId)
        external
        view
        returns (uint256 balance)
    {
        return clearingHouse.getAccountCollateralBalance(accountId, collateralId);
    }

    function getAccountTokenPositionInfo(uint256 accountId, uint32 poolId)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumALastX128
        )
    {
        return clearingHouse.getAccountTokenPositionInfo(accountId, poolId);
    }

    function getAccountPositionInfo(uint256 accountId, uint32 poolId)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumALastX128,
            ClearingHouseExtsload.TickRange[] memory activeTickRanges
        )
    {
        return clearingHouse.getAccountPositionInfo(accountId, poolId);
    }

    function getAccountLiquidityPositionList(uint256 accountId, uint32 poolId)
        external
        view
        returns (ClearingHouseExtsload.TickRange[] memory activeTickRanges)
    {
        return clearingHouse.getAccountLiquidityPositionList(accountId, poolId);
    }

    function getAccountLiquidityPositionInfo(
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        returns (
            uint8 limitOrderType,
            uint128 liquidity,
            int256 vTokenAmountIn,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        return clearingHouse.getAccountLiquidityPositionInfo(accountId, poolId, tickLower, tickUpper);
    }
}
