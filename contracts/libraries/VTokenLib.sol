//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { DEFAULT_FEE_TIER, VBASE_ADDRESS, UNISWAP_FACTORY_ADDRESS, VPOOL_FACTORY, POOL_BYTE_CODE_HASH, WRAPPER_BYTE_CODE_HASH } from '../Constants.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IOracleContract } from '../interfaces/IOracleContract.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Oracle } from '../libraries/Oracle.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

type VToken is address;

library VTokenLib {
    function isToken0(VToken vToken) internal pure returns (bool) {
        return VToken.unwrap(vToken) < VBASE_ADDRESS;
    }

    function isToken1(VToken vToken) internal pure returns (bool) {
        return !isToken0(vToken);
    }

    function vPool(VToken vToken) internal pure returns (address) {
        address token0;
        address token1;
        address vTokenAddress = VToken.unwrap(vToken);

        if (isToken0(vToken)) {
            token0 = vTokenAddress;
            token1 = VBASE_ADDRESS;
        } else {
            token0 = VBASE_ADDRESS;
            token1 = vTokenAddress;
        }
        return
            Create2.computeAddress(
                keccak256(abi.encode(token0, token1, DEFAULT_FEE_TIER)),
                POOL_BYTE_CODE_HASH,
                UNISWAP_FACTORY_ADDRESS
            );
    }

    function vPoolWrapper(VToken vToken) internal pure returns (address) {
        return
            Create2.computeAddress(
                keccak256(abi.encode(VToken.unwrap(vToken), VBASE_ADDRESS)),
                WRAPPER_BYTE_CODE_HASH,
                VPOOL_FACTORY
            );
    }

    function realToken(VToken vToken) internal view returns (address) {
        return IVToken(VToken.unwrap(vToken)).realToken();
    }

    function getVirtualTwapSqrtPrice(VToken vToken) internal view returns (uint160) {
        IVPoolWrapper poolWrapper = IVPoolWrapper(vPoolWrapper(vToken));
        return getVirtualTwapSqrtPrice(vToken, poolWrapper.timeHorizon());
    }

    function getRealTwapSqrtPrice(VToken vToken) internal view returns (uint160) {
        IVPoolWrapper poolWrapper = IVPoolWrapper(vPoolWrapper(vToken));
        return getRealTwapSqrtPrice(vToken, poolWrapper.timeHorizon());
    }

    function getVirtualTwapSqrtPrice(VToken vToken, uint32 twapDuration) internal view returns (uint160) {
        return Oracle.getAverageSqrtPrice(IUniswapV3Pool(vPool(vToken)), twapDuration);
    }

    function getRealTwapSqrtPrice(VToken vToken, uint32 twapDuration) internal view returns (uint160) {
        address oracle = IVToken(VToken.unwrap(vToken)).oracle();
        return IOracleContract(oracle).getSqrtPrice(twapDuration);
    }

    function getMarginRatio(VToken vToken, bool isInitialMargin) internal view returns (uint16) {
        IVPoolWrapper poolWrapper = IVPoolWrapper(vPoolWrapper(vToken));
        if (isInitialMargin) {
            return poolWrapper.initialMarginRatio();
        } else {
            return poolWrapper.maintainanceMarginRatio();
        }
    }
}
