// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { PriceMath } from './PriceMath.sol';
import { SafeCast } from './SafeCast.sol';
import { SignedMath } from './SignedMath.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';

import { SafeCast } from './SafeCast.sol';

interface ArbSys {
    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);
}

/// @title Protocol storage functions
/// @dev This is used as main storage interface containing protocol info
library Protocol {
    using FullMath for uint256;
    using PriceMath for uint160;
    using PriceMath for uint256;
    using SignedMath for int256;
    using SignedFullMath for int256;
    using SafeCast for uint256;
    using UniswapV3PoolHelper for IUniswapV3Pool;
    using SafeCast for uint256;

    using Protocol for Protocol.Info;

    struct PriceCache {
        uint32 updateBlockNum;
        uint224 virtualPriceX128;
        uint224 realPriceX128;
        bool isDeviationBreached;
    }
    struct Info {
        // poolId => PoolInfo
        mapping(uint32 => IClearingHouseStructures.Pool) pools;
        // collateralId => CollateralInfo
        mapping(uint32 => IClearingHouseStructures.Collateral) collaterals;
        // iterable and increasing list of pools (used for admin functions)
        uint32[] poolIds;
        // settlement token (default collateral)
        IERC20 settlementToken;
        // virtual quote token (sort of fake USDC), is always token1 in uniswap pools
        IVQuote vQuote;
        // accounting settings
        IClearingHouseStructures.LiquidationParams liquidationParams;
        uint256 minRequiredMargin;
        uint256 removeLimitOrderFee;
        uint256 minimumOrderNotional;
        // price cache
        mapping(uint32 => PriceCache) priceCache;
        // reserved for adding slots in future
        uint256[100] _emptySlots;
    }

    function getBlockNumber() internal view returns (uint32) {
        return uint32(ArbSys(address(100)).arbBlockNumber());
    }

    function updatePoolPriceCache(Protocol.Info storage protocol, uint32 poolId) internal {
        uint32 curArbBlockNum = getBlockNumber();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNum == curArbBlockNum) {
            return;
        }

        uint256 realPriceX128 = protocol.getRealTwapPriceX128(poolId);
        uint256 virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);

        uint16 maxDeviationBps = protocol.pools[poolId].settings.maxVirtualPriceDeviationRatioBps;
        if (
            // if virtual price is too off from real price then screw that, we'll just use real price
            (int256(realPriceX128) - int256(virtualPriceX128)).absUint() > realPriceX128.mulDiv(maxDeviationBps, 1e4)
        ) {
            poolPriceCache.isDeviationBreached = true;
        }
        poolPriceCache.realPriceX128 = realPriceX128.toUint224();
        poolPriceCache.virtualPriceX128 = virtualPriceX128.toUint224();
        poolPriceCache.updateBlockNum = curArbBlockNum;
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

    function getRealTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        IClearingHouseStructures.Pool storage pool = protocol.pools[poolId];
        return pool.settings.oracle.getTwapPriceX128(pool.settings.twapDuration);
    }

    function getTwapPricesWithDeviationCheck(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        realPriceX128 = protocol.getRealTwapPriceX128(poolId);
        virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);

        uint16 maxDeviationBps = protocol.pools[poolId].settings.maxVirtualPriceDeviationRatioBps;
        uint256 priceDeltaX128 = realPriceX128 > virtualPriceX128
            ? realPriceX128 - virtualPriceX128
            : virtualPriceX128 - realPriceX128;
        if (priceDeltaX128 > realPriceX128.mulDiv(maxDeviationBps, 1e4)) {
            // if virtual price is too off from real price then screw that, we'll just use real price
            virtualPriceX128 = realPriceX128;
        }
        return (realPriceX128, virtualPriceX128);
    }

    function getCachedVirtualTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        uint32 curArbBlockNum = getBlockNumber();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNum == curArbBlockNum) {
            return poolPriceCache.virtualPriceX128;
        } else {
            return protocol.getVirtualTwapPriceX128(poolId);
        }
    }

    function getCachedTwapPricesWithDeviationCheck(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        uint32 curArbBlockNum = getBlockNumber();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNum == curArbBlockNum) {
            if (poolPriceCache.isDeviationBreached) {
                return (poolPriceCache.realPriceX128, poolPriceCache.virtualPriceX128);
            } else {
                return (poolPriceCache.realPriceX128, poolPriceCache.realPriceX128);
            }
        } else {
            return protocol.getTwapPricesWithDeviationCheck(poolId);
        }
    }

    function getCachedRealTwapPriceX128(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        uint32 curArbBlockNum = getBlockNumber();

        PriceCache storage poolPriceCache = protocol.priceCache[poolId];
        if (poolPriceCache.updateBlockNum == curArbBlockNum) {
            return poolPriceCache.realPriceX128;
        } else {
            return protocol.getRealTwapPriceX128(poolId);
        }
    }

    function getMarginRatioBps(
        Protocol.Info storage protocol,
        uint32 poolId,
        bool isInitialMargin
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return protocol.pools[poolId].settings.initialMarginRatioBps;
        } else {
            return protocol.pools[poolId].settings.maintainanceMarginRatioBps;
        }
    }

    function isPoolCrossMargined(Protocol.Info storage protocol, uint32 poolId) internal view returns (bool) {
        return protocol.pools[poolId].settings.isCrossMargined;
    }

    /// @notice Gives notional value of the given vToken and vQuote amounts
    /// @param protocol platform constants
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of tokens
    /// @param vQuoteAmount amount of base
    /// @return notionalValue for the given token and vQuote amounts
    function getNotionalValue(
        Protocol.Info storage protocol,
        uint32 poolId,
        int256 vTokenAmount,
        int256 vQuoteAmount
    ) internal view returns (uint256 notionalValue) {
        return
            vTokenAmount.absUint().mulDiv(protocol.getVirtualTwapPriceX128(poolId), FixedPoint128.Q128) +
            vQuoteAmount.absUint();
    }

    /// @notice Gives notional value of the given token amount
    /// @param protocol platform constants
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of tokens
    /// @return notionalValue for the given token and vQuote amounts
    function getNotionalValue(
        Protocol.Info storage protocol,
        uint32 poolId,
        int256 vTokenAmount
    ) internal view returns (uint256 notionalValue) {
        return protocol.getNotionalValue(poolId, vTokenAmount, 0);
    }
}
