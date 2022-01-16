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

import { console } from 'hardhat/console.sol';

library VTokenLib {
    using VTokenLib for IVToken;
    using FullMath for uint256;
    using PriceMath for uint160;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    function eq(IVToken a, IVToken b) internal pure returns (bool) {
        return address(a) == address(b);
    }

    function eq(IVToken a, address b) internal pure returns (bool) {
        return address(a) == b;
    }

    function truncate(IVToken vToken) internal pure returns (uint32) {
        return uint32(uint160(address(vToken)));
    }

    function iface(IVToken vToken) internal pure returns (IVToken) {
        return IVToken(address(vToken));
    }

    function vPool(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (IUniswapV3Pool)
    {
        return protocol.pools[vToken].vPool;
    }

    function vPoolWrapper(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (IVPoolWrapper)
    {
        return protocol.pools[vToken].vPoolWrapper;
    }

    function getVirtualTwapSqrtPriceX96(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[vToken].vPool.twapSqrtPrice(protocol.pools[vToken].settings.twapDuration);
    }

    function getVirtualCurrentSqrtPriceX96(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return protocol.pools[vToken].vPool.sqrtPriceCurrent();
    }

    function getVirtualTwapTick(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int24 tick)
    {
        return protocol.pools[vToken].vPool.twapTick(protocol.pools[vToken].settings.twapDuration);
    }

    function getVirtualTwapPriceX128(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getVirtualTwapSqrtPriceX96(protocol).toPriceX128();
    }

    function getVirtualCurrentPriceX128(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getVirtualCurrentSqrtPriceX96(protocol).toPriceX128();
    }

    function getRealTwapSqrtPriceX96(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return
            protocol.pools[vToken].settings.oracle.getTwapSqrtPriceX96(
                protocol.pools[vToken].settings.twapDuration
            );
    }

    function getRealTwapPriceX128(IVToken vToken, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getRealTwapSqrtPriceX96(protocol).toPriceX128();
    }

    function getMarginRatio(
        IVToken vToken,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return protocol.pools[vToken].settings.initialMarginRatio;
        } else {
            return protocol.pools[vToken].settings.maintainanceMarginRatio;
        }
    }

    function getWhitelisted(IVToken vToken, Account.ProtocolInfo storage protocol) internal view returns (bool) {
        return protocol.pools[vToken].settings.whitelisted;
    }
}
