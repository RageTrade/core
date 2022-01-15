//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { PriceMath } from './PriceMath.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

// TODO remove dependency from protocol
import { AccountStorage } from '../protocol/clearinghouse/ClearingHouseStorage.sol';

import { console } from 'hardhat/console.sol';

type VTokenAddress is address;

library VTokenLib {
    using VTokenLib for VTokenAddress;
    using FullMath for uint256;
    using PriceMath for uint160;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    function eq(VTokenAddress a, VTokenAddress b) internal pure returns (bool) {
        return VTokenAddress.unwrap(a) == VTokenAddress.unwrap(b);
    }

    function eq(VTokenAddress a, address b) internal pure returns (bool) {
        return VTokenAddress.unwrap(a) == b;
    }

    function truncate(VTokenAddress vToken) internal pure returns (uint32) {
        return uint32(uint160(VTokenAddress.unwrap(vToken)));
    }

    function iface(VTokenAddress vToken) internal pure returns (IVToken) {
        return IVToken(VTokenAddress.unwrap(vToken));
    }

    function vPool(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (IUniswapV3Pool)
    {
        return accountStorage.rtPools[vTokenAddress].vPool;
    }

    function vPoolWrapper(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (IVPoolWrapper)
    {
        return accountStorage.rtPools[vTokenAddress].vPoolWrapper;
    }

    function getVirtualTwapSqrtPriceX96(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return
            accountStorage.rtPools[vTokenAddress].vPool.twapSqrtPrice(
                accountStorage.rtPools[vTokenAddress].settings.twapDuration
            );
    }

    function getVirtualCurrentSqrtPriceX96(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return accountStorage.rtPools[vTokenAddress].vPool.sqrtPriceCurrent();
    }

    function getVirtualTwapTick(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (int24 tick)
    {
        return
            accountStorage.rtPools[vTokenAddress].vPool.twapTick(
                accountStorage.rtPools[vTokenAddress].settings.twapDuration
            );
    }

    function getVirtualTwapPriceX128(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint256 priceX128)
    {
        return vTokenAddress.getVirtualTwapSqrtPriceX96(accountStorage).toPriceX128();
    }

    function getVirtualCurrentPriceX128(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint256 priceX128)
    {
        return vTokenAddress.getVirtualCurrentSqrtPriceX96(accountStorage).toPriceX128();
    }

    function getRealTwapSqrtPriceX96(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return
            accountStorage.rtPools[vTokenAddress].settings.oracle.getTwapSqrtPriceX96(
                accountStorage.rtPools[vTokenAddress].settings.twapDuration
            );
    }

    function getRealTwapPriceX128(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (uint256 priceX128)
    {
        return vTokenAddress.getRealTwapSqrtPriceX96(accountStorage).toPriceX128();
    }

    function getMarginRatio(
        VTokenAddress vTokenAddress,
        bool isInitialMargin,
        AccountStorage storage accountStorage
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return accountStorage.rtPools[vTokenAddress].settings.initialMarginRatio;
        } else {
            return accountStorage.rtPools[vTokenAddress].settings.maintainanceMarginRatio;
        }
    }

    function getWhitelisted(VTokenAddress vTokenAddress, AccountStorage storage accountStorage)
        internal
        view
        returns (bool)
    {
        return accountStorage.rtPools[vTokenAddress].settings.whitelisted;
    }
}
