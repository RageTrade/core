//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { DEFAULT_FEE_TIER, VBASE_ADDRESS, UNISWAP_FACTORY_ADDRESS, VPOOL_FACTORY, POOL_BYTE_CODE_HASH } from '../Constants.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Oracle } from '../libraries/Oracle.sol';
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import 'hardhat/console.sol';

type VTokenAddress is address;

library VTokenLib2 {
    using VTokenLib2 for VTokenAddress;
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

    function flip(
        VTokenAddress vToken,
        int256 amount0,
        int256 amount1
    ) internal pure returns (int256 baseAmount, int256 vTokenAmount) {
        if (vToken.isToken0()) {
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
        uint256 amount1
    ) internal pure returns (uint256 baseAmount, uint256 vTokenAmount) {
        if (vToken.isToken0()) {
            baseAmount = amount1;
            vTokenAmount = amount0;
        } else {
            baseAmount = amount0;
            vTokenAmount = amount1;
        }
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
}
