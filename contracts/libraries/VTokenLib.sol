//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { DEFAULT_FEE_TIER, VBASE_ADDRESS, UNISWAP_FACTORY_ADDRESS, VPOOL_FACTORY, POOL_BYTE_CODE_HASH, WRAPPER_BYTE_CODE_HASH } from '../Constants.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Oracle } from '../libraries/Oracle.sol';
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IOracleContract } from '../interfaces/IOracleContract.sol';

type VTokenAddress is address;

library VTokenLib {
    using VTokenLib for VTokenAddress;
    using FullMath for uint256;

    function iface(VTokenAddress vToken) internal pure returns (IVToken) {
        return IVToken(VTokenAddress.unwrap(vToken));
    }

    function realToken(VTokenAddress vToken) internal view returns (IERC20) {
        return IERC20(vToken.iface().realToken());
    }

    function isToken0(VTokenAddress vToken) internal pure returns (bool) {
        return VTokenAddress.unwrap(vToken) < VBASE_ADDRESS;
    }

    function isToken1(VTokenAddress vToken) internal pure returns (bool) {
        return !isToken0(vToken);
    }

    function vPool(
        VTokenAddress vToken,
        bytes32 POOL_BYTE_CODE_HASH_,
        address UNISWAP_FACTORY_ADDRESS_
    ) internal pure returns (IUniswapV3Pool) {
        address token0;
        address token1;
        address vTokenAddress = VTokenAddress.unwrap(vToken);

        if (vToken.isToken0()) {
            token0 = vTokenAddress;
            token1 = VBASE_ADDRESS;
        } else {
            token0 = VBASE_ADDRESS;
            token1 = vTokenAddress;
        }
        return
            IUniswapV3Pool(
                Create2.computeAddress(
                    keccak256(abi.encode(token0, token1, DEFAULT_FEE_TIER)),
                    POOL_BYTE_CODE_HASH_,
                    UNISWAP_FACTORY_ADDRESS_
                )
            );
    }

    // overload
    function vPool(VTokenAddress vToken) internal pure returns (IUniswapV3Pool) {
        return vToken.vPool(POOL_BYTE_CODE_HASH, UNISWAP_FACTORY_ADDRESS);
    }

    function vPoolWrapper(
        VTokenAddress vToken,
        bytes32 WRAPPER_BYTE_CODE_HASH_,
        address VPOOL_FACTORY_
    ) internal pure returns (IVPoolWrapper) {
        return
            IVPoolWrapper(
                Create2.computeAddress(
                    keccak256(abi.encode(VTokenAddress.unwrap(vToken), VBASE_ADDRESS)),
                    WRAPPER_BYTE_CODE_HASH_,
                    VPOOL_FACTORY_
                )
            );
    }

    // overload
    function vPoolWrapper(VTokenAddress vToken) internal pure returns (IVPoolWrapper) {
        return vToken.vPoolWrapper(WRAPPER_BYTE_CODE_HASH, VPOOL_FACTORY);
    }

    function getVirtualTwapSqrtPrice(VTokenAddress vToken) internal view returns (uint160 sqrtPriceX96) {
        return Oracle.getTwapSqrtPrice(vToken.vPool(), vToken.vPoolWrapper().timeHorizon());
    }

    function getRealTwapSqrtPrice(VTokenAddress vToken) internal view returns (uint160 sqrtPriceX96) {
        return IOracleContract(vToken.iface().oracle()).getTwapSqrtPrice(vToken.vPoolWrapper().timeHorizon());
    }

    function getVirtualTwapTick(VTokenAddress vToken) internal view returns (int24 tick) {
        return Oracle.getTwapTick(vToken.vPool(), vToken.vPoolWrapper().timeHorizon());
    }

    function getVirtualTwapPrice(VTokenAddress vToken) internal view returns (uint256 price) {
        uint256 sqrtPriceX96 = vToken.getVirtualTwapSqrtPrice();
        return sqrtPriceX96.mulDiv(sqrtPriceX96, FixedPoint96.Q96); // TODO refactor this
    }

    function getRealTwapPrice(VTokenAddress vToken) internal view returns (uint256 price) {
        uint256 sqrtPriceX96 = vToken.getRealTwapSqrtPrice();
        return sqrtPriceX96.mulDiv(sqrtPriceX96, FixedPoint96.Q96); // TODO refactor this
    }

    function getMarginRatio(VTokenAddress vToken, bool isInitialMargin) internal view returns (uint16) {
        if (isInitialMargin) {
            return vToken.vPoolWrapper().initialMarginRatio();
        } else {
            return vToken.vPoolWrapper().maintainanceMarginRatio();
        }
    }
}
