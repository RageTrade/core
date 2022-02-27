//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { Account } from './Account.sol';
import { PriceMath } from './PriceMath.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import { PriceMath } from './PriceMath.sol';
import { console } from 'hardhat/console.sol';

library PoolIdHelper {
    using PoolIdHelper for uint32;
    using FullMath for uint256;
    using PriceMath for uint160;
    using PriceMath for uint256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    function vToken(uint32 poolId, Account.ProtocolInfo storage protocol) internal view returns (IUniswapV3Pool) {
        return protocol.pools[poolId].vPool;
    }

    function vPool(uint32 poolId, Account.ProtocolInfo storage protocol) internal view returns (IUniswapV3Pool) {
        return protocol.pools[poolId].vPool;
    }

    function vPoolWrapper(uint32 poolId, Account.ProtocolInfo storage protocol) internal view returns (IVPoolWrapper) {
        return protocol.pools[poolId].vPoolWrapper;
    }

    function getVirtualTwapSqrtPriceX96(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.twapSqrtPrice(protocol.pools[poolId].settings.twapDuration);
    }

    function getVirtualCurrentSqrtPriceX96(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[poolId].vPool.sqrtPriceCurrent();
    }

    function getVirtualCurrentTick(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int24 tick)
    {
        return protocol.pools[poolId].vPool.tickCurrent();
    }

    function getVirtualTwapTick(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int24 tick)
    {
        return protocol.pools[poolId].vPool.twapTick(protocol.pools[poolId].settings.twapDuration);
    }

    function getVirtualTwapPriceX128(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return poolId.getVirtualTwapSqrtPriceX96(protocol).toPriceX128();
    }

    function getVirtualCurrentPriceX128(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return poolId.getVirtualCurrentSqrtPriceX96(protocol).toPriceX128();
    }

    function getRealTwapSqrtPriceX96(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return poolId.getRealTwapPriceX128(protocol).toSqrtPriceX96();
    }

    function getRealTwapPriceX128(uint32 poolId, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return protocol.pools[poolId].settings.oracle.getTwapPriceX128(protocol.pools[poolId].settings.twapDuration);
    }

    function getMarginRatio(
        uint32 poolId,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return protocol.pools[poolId].settings.initialMarginRatio;
        } else {
            return protocol.pools[poolId].settings.maintainanceMarginRatio;
        }
    }

    function isCrossMargined(uint32 poolId, Account.ProtocolInfo storage protocol) internal view returns (bool) {
        return protocol.pools[poolId].settings.isCrossMargined;
    }
}
