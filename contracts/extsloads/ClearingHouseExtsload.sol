// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IExtsload } from '../interfaces/IExtsload.sol';
import { IOracle } from '../interfaces/IOracle.sol';

import { WordHelper } from '../libraries/WordHelper.sol';

library ClearingHouseExtsload {
    using WordHelper for bytes32;
    using WordHelper for WordHelper.Word;

    bytes32 constant PROTOCOL_SLOT = bytes32(uint256(100));
    bytes32 constant POOLS_MAPPING_SLOT = PROTOCOL_SLOT;

    function getVPool(IClearingHouse clearingHouse, uint32 poolId) internal view returns (IUniswapV3Pool vPool) {
        bytes32 result = clearingHouse.extsload(keyOfVPool(poolId));
        assembly {
            vPool := result
        }
    }

    function getPoolSettings(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IClearingHouse.PoolSettings memory settings)
    {
        WordHelper.Word memory result = clearingHouse.extsload(keyOfPoolSettings(poolId)).copyToMemory();

        settings.initialMarginRatioBps = result.popUint16();
        settings.maintainanceMarginRatioBps = result.popUint16();
        settings.maxVirtualPriceDeviationRatioBps = result.popUint16();
        settings.twapDuration = result.popUint32();
        settings.isAllowedForTrade = result.popBool();
        settings.isCrossMargined = result.popBool();
        settings.oracle = IOracle(result.popAddress());
    }

    function getTwapDuration(IClearingHouse clearingHouse, uint32 poolId) internal view returns (uint32 twapDuration) {
        bytes32 result = clearingHouse.extsload(keyOfPoolSettings(poolId));
        twapDuration = uint32(result.slice(0x30, 0x50));
    }

    function getVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        bytes32[] memory arr = new bytes32[](2);
        arr[0] = keyOfVPool(poolId);
        arr[1] = keyOfPoolSettings(poolId);
        arr = clearingHouse.extsload(arr);

        vPool = IUniswapV3Pool(arr[0].toAddress());
        twapDuration = uint32(arr[1].slice(0xB0, 0xD0));
    }

    // KEY GENERATORS

    function keyOfVPool(uint32 poolId) internal pure returns (bytes32) {
        return WordHelper.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(1);
    }

    function keyOfPoolSettings(uint32 poolId) internal pure returns (bytes32) {
        return WordHelper.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(3);
    }
}
