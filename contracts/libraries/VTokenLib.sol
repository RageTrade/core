//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Oracle } from './Oracle.sol';
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
import { PriceMath } from './PriceMath.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IOracle } from '../interfaces/IOracle.sol';

import { Constants } from '../utils/Constants.sol';

type VTokenAddress is address;

library VTokenLib {
    using VTokenLib for VTokenAddress;
    using FullMath for uint256;
    using PriceMath for uint160;

    function iface(VTokenAddress vToken) internal pure returns (IVToken) {
        return IVToken(VTokenAddress.unwrap(vToken));
    }

    function realToken(VTokenAddress vToken) internal view returns (IERC20) {
        return IERC20(vToken.iface().realToken());
    }

    function isToken0(VTokenAddress vToken, Constants memory constants) internal pure returns (bool) {
        return VTokenAddress.unwrap(vToken) < constants.VBASE_ADDRESS;
    }

    function isToken1(VTokenAddress vToken, Constants memory constants) internal pure returns (bool) {
        return !isToken0(vToken, constants);
    }

    function flip(
        VTokenAddress vToken,
        int256 amount0,
        int256 amount1,
        Constants memory constants
    ) internal pure returns (int256 baseAmount, int256 vTokenAmount) {
        if (vToken.isToken0(constants)) {
            baseAmount = amount1;
            vTokenAmount = amount0;
        } else {
            baseAmount = amount0;
            vTokenAmount = amount1;
        }
    }

    function flip(
        VTokenAddress vToken,
        uint256 amount0,
        uint256 amount1,
        Constants memory constants
    ) internal pure returns (uint256 baseAmount, uint256 vTokenAmount) {
        if (vToken.isToken0(constants)) {
            baseAmount = amount1;
            vTokenAmount = amount0;
        } else {
            baseAmount = amount0;
            vTokenAmount = amount1;
        }
    }

    function vPool(VTokenAddress vToken, Constants memory constants) internal pure returns (IUniswapV3Pool) {
        address token0;
        address token1;
        address vTokenAddress = VTokenAddress.unwrap(vToken);

        if (vToken.isToken0(constants)) {
            token0 = vTokenAddress;
            token1 = constants.VBASE_ADDRESS;
        } else {
            token0 = constants.VBASE_ADDRESS;
            token1 = vTokenAddress;
        }
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
        // console.log(VTokenAddress.unwrap(vToken), address(vToken.vPoolWrapper()));
        return Oracle.getTwapSqrtPrice(vToken.vPool(constants), vToken.vPoolWrapper(constants).timeHorizon());
    }

    function getVirtualTwapTick(VTokenAddress vToken, Constants memory constants) internal view returns (int24 tick) {
        return Oracle.getTwapTick(vToken.vPool(constants), vToken.vPoolWrapper(constants).timeHorizon());
    }

    function getVirtualTwapPriceX128(VTokenAddress vToken, Constants memory constants)
        internal
        view
        returns (uint256 priceX128)
    {
        return vToken.getVirtualTwapSqrtPriceX96(constants).toPriceX128(vToken.isToken0(constants));
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
        return vToken.getRealTwapSqrtPriceX96(constants).toPriceX128(vToken.isToken0(constants));
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
}
