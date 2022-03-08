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

    function vTokenFor(Protocol.Info storage protocol, uint32 poolId) internal view returns (IVToken) {
        return protocol.pools[poolId].vToken;
    }

    function vPoolFor(Protocol.Info storage protocol, uint32 poolId) internal view returns (IUniswapV3Pool) {
        return protocol.pools[poolId].vPool;
    }

    function vPoolWrapperFor(Protocol.Info storage protocol, uint32 poolId) internal view returns (IVPoolWrapper) {
        return protocol.pools[poolId].vPoolWrapper;
    }

    function getVirtualTwapSqrtPriceX96For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.twapSqrtPrice(protocol.pools[poolId].settings.twapDuration);
    }

    function getVirtualCurrentSqrtPriceX96For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.sqrtPriceCurrent();
    }

    function getVirtualCurrentTickFor(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (int24 tick)
    {
        return protocol.pools[poolId].vPool.tickCurrent();
    }

    function getVirtualTwapTickFor(Protocol.Info storage protocol, uint32 poolId) internal view returns (int24 tick) {
        return protocol.pools[poolId].vPool.twapTick(protocol.pools[poolId].settings.twapDuration);
    }

    function getVirtualTwapPriceX128For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualTwapSqrtPriceX96For(poolId).toPriceX128();
    }

    function getVirtualCurrentPriceX128For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.getVirtualCurrentSqrtPriceX96For(poolId).toPriceX128();
    }

    function getRealTwapSqrtPriceX96For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.getRealTwapPriceX128For(poolId).toSqrtPriceX96();
    }

    function getRealTwapPriceX128For(Protocol.Info storage protocol, uint32 poolId)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.pools[poolId].settings.oracle.getTwapPriceX128(protocol.pools[poolId].settings.twapDuration);
    }

    function getMarginRatioFor(
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
