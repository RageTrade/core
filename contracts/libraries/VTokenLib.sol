//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { PriceMath } from './PriceMath.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { Constants } from '../utils/Constants.sol';

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

    function realToken(VTokenAddress vToken) internal view returns (IERC20) {
        return IERC20(vToken.iface().realToken());
    }

    function vPool(VTokenAddress vToken, Constants memory constants) internal pure returns (IUniswapV3Pool) {
        address token0;
        address token1;
        address vTokenAddress = VTokenAddress.unwrap(vToken);

        token0 = vTokenAddress;
        token1 = constants.VBASE_ADDRESS;

        return
            IUniswapV3Pool(
                Create2.computeAddress(
                    keccak256(abi.encode(token0, token1, constants.DEFAULT_FEE_TIER)),
                    constants.POOL_BYTE_CODE_HASH,
                    constants.UNISWAP_FACTORY_ADDRESS
                )
            );
    }

    // // overload
    // function vPool(VTokenAddress vToken, address VBASE_ADDRESS, ) internal pure returns (IUniswapV3Pool) {
    //     return vToken.vPool(POOL_BYTE_CODE_HASH, UNISWAP_FACTORY_ADDRESS);
    // }

    function vPoolWrapper(VTokenAddress vToken, Constants memory constants) internal pure returns (IVPoolWrapper) {
        return
            IVPoolWrapper(
                Create2.computeAddress(
                    keccak256(abi.encode(VTokenAddress.unwrap(vToken), constants.VBASE_ADDRESS)),
                    constants.WRAPPER_BYTE_CODE_HASH,
                    constants.VPOOL_WRAPPER_DEPLOYER
                )
            );
    }

    function getVirtualTwapSqrtPriceX96(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return vToken.vPool(constants).twapSqrtPrice(vToken.vPoolWrapper(constants).timeHorizon());
    }

    function getVirtualCurrentSqrtPriceX96(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return vToken.vPool(constants).sqrtPriceCurrent();
    }

    function getVirtualTwapTick(VTokenAddress vToken, Constants memory constants) internal view returns (int24 tick) {
        return vToken.vPool(constants).twapTick(vToken.vPoolWrapper(constants).timeHorizon());
    }

    function getVirtualTwapPriceX128(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getVirtualTwapSqrtPriceX96(constants).toPriceX128();
    }

    function getVirtualCurrentPriceX128(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getVirtualCurrentSqrtPriceX96(constants).toPriceX128();
    }

    function getRealTwapSqrtPriceX96(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        return IOracle(vToken.iface().oracle()).getTwapSqrtPriceX96(vToken.vPoolWrapper(constants).timeHorizon());
    }

    function getRealTwapPriceX128(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getRealTwapSqrtPriceX96(constants).toPriceX128();
    }

    function getMarginRatio(
        VTokenAddress vToken,
        bool isInitialMargin,
        Constants memory constants
    ) internal view returns (uint16) {
        if (isInitialMargin) {
            return vToken.vPoolWrapper(constants).initialMarginRatio();
        } else {
            return vToken.vPoolWrapper(constants).maintainanceMarginRatio();
        }
    }

    function getWhitelisted(VTokenAddress vToken, Constants memory constants) internal view returns (bool) {
        return vToken.vPoolWrapper(constants).whitelisted();
    }
}
