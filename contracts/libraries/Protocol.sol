// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { PriceMath } from './PriceMath.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';

library Protocol {
    using PriceMath for uint160;
    using PriceMath for uint256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    using Protocol for Protocol.Info;

    struct Info {
        // poolId => PoolInfo
        mapping(uint32 => IClearingHouseStructures.Pool) pools;
        // collateralId => CollateralInfo
        mapping(uint32 => IClearingHouseStructures.Collateral) collaterals;
        // settlement token (default collateral)
        IERC20 settlementToken;
        // virtual quote token (sort of fake USDC), is always token1 in uniswap pools
        IVQuote vQuote;
        // accounting settings
        IClearingHouseStructures.LiquidationParams liquidationParams;
        uint256 minRequiredMargin;
        uint256 removeLimitOrderFee;
        uint256 minimumOrderNotional;
        // reserved for adding slots in future
        uint256[100] _emptySlots;
    }

    function vToken(Protocol.Info storage protocol, uint32 poolId) internal view returns (IVToken) {
        return protocol.pools[poolId].vToken;
    }

    function vPool(Protocol.Info storage protocol, uint32 poolId) internal view returns (IUniswapV3Pool) {
        return protocol.pools[poolId].vPool;
    }

    function vPoolWrapper(Protocol.Info storage protocol, uint32 poolId) internal view returns (IVPoolWrapper) {
        return protocol.pools[poolId].vPoolWrapper;
    }

    function getVirtualTwapSqrtPriceX96(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.vPool.twapSqrtPrice(pool.settings.twapDuration);
    }

    function getVirtualCurrentSqrtPriceX96(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.sqrtPriceCurrent();
    }

    function getVirtualCurrentTick(Protocol.Info storage protocol, uint32 poolId) internal view returns (int24 tick) {
        return protocol.pools[poolId].vPool.tickCurrent();
    }

    function getVirtualTwapTick(Protocol.Info storage protocol, uint32 poolId) internal view returns (int24 tick) {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.vPool.twapTick(pool.settings.twapDuration);
    }

    function getVirtualTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualTwapSqrtPriceX96(poolId).toPriceX128();
    }

    function getVirtualCurrentPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualCurrentSqrtPriceX96(poolId).toPriceX128();
    }

    function getRealTwapSqrtPriceX96(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.getRealTwapPriceX128(poolId).toSqrtPriceX96();
    }

    function getRealTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.settings.oracle.getTwapPriceX128(pool.settings.twapDuration);
    }

    function getMarginRatio(
        Protocol.Info storage protocol,
        uint32 poolId,
        bool isInitialMargin
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return protocol.pools[poolId].settings.initialMarginRatio;
        } else {
            return protocol.pools[poolId].settings.maintainanceMarginRatio;
        }
    }

    function isPoolCrossMargined(Protocol.Info storage protocol, uint32 poolId) internal view returns (bool) {
        return protocol.pools[poolId].settings.isCrossMargined;
    }
}
