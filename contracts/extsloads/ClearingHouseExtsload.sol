// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IExtsload } from '../interfaces/IExtsload.sol';
import { IClearingHouse } from '../interfaces/IClearingHouse.sol';

import { Bytes32 } from '../libraries/Bytes32.sol';

import 'hardhat/console.sol';

library ClearingHouseExtsload {
    using Bytes32 for bytes32;

    bytes32 constant PROTOCOL_SLOT = bytes32(uint256(100));

    bytes32 constant POOLS_MAPPING_SLOT = PROTOCOL_SLOT;

    // uint256 constant COLLATERAL_MAPPING_SLOT = PROTOCOL_SLOT + 1;
    // uint256 constant SETTLEMENT_TOKEN_SLOT = PROTOCOL_SLOT + 2;

    // vPool

    function pools_vPool(IClearingHouse clearingHouse, uint32 poolId) internal view returns (address vPool) {
        bytes32 result = clearingHouse.extsload(pools_vPool_key(poolId));
        assembly {
            vPool := result
        }
    }

    function pools_settings(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (
            uint16 initialMarginRatioBps,
            uint16 maintainanceMarginRatioBps,
            uint16 maxVirtualPriceDeviationRatioBps,
            uint32 twapDuration,
            bool isAllowedForTrade,
            bool isCrossMargined,
            address oracle
        )
    {
        bytes32 result = clearingHouse.extsload(pools_settings_key(poolId));

        (initialMarginRatioBps, result) = result.extractUint16();
        (maintainanceMarginRatioBps, result) = result.extractUint16();
        (maxVirtualPriceDeviationRatioBps, result) = result.extractUint16();
        (twapDuration, result) = result.extractUint32();
        (isAllowedForTrade, result) = result.extractBool();
        (isCrossMargined, result) = result.extractBool();
        (oracle, result) = result.extractAddress();
    }

    function pools_settings_twapDuration(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (uint32 twapDuration)
    {
        bytes32 result = clearingHouse.extsload(pools_settings_key(poolId));
        twapDuration = uint32(result.slice(0x30, 0x50));
    }

    function pools_settings_key(uint32 poolId) internal pure returns (bytes32) {
        return Bytes32.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(3);
    }

    function pools_vPool_key(uint32 poolId) internal pure returns (bytes32) {
        return Bytes32.fromUint(poolId).keccak256Two(POOLS_MAPPING_SLOT).offset(1);
    }

    // custom

    function pools_vPool_and_settings_twapDuration(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (address vPool, uint32 twapDuration)
    {
        bytes32[] memory arr = new bytes32[](2);
        arr[0] = pools_vPool_key(poolId);
        arr[1] = pools_settings_key(poolId);
        arr = clearingHouse.extsload(arr);
        (vPool, ) = arr[0].extractAddress();
        twapDuration = uint32(arr[1].slice(0xB0, 0xD0));
    }
}
