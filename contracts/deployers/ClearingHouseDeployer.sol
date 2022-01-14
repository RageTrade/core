//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { ProxyAdminDeployer } from './ProxyAdminDeployer.sol';

import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IRageTradeFactory } from '../interfaces/IRageTradeFactory.sol';

import { Governable } from '../utils/Governable.sol';

/// @notice Manages deployment for ClearingHouseProxy
/// @dev ClearingHouse proxy is deployed only once
abstract contract ClearingHouseDeployer is IRageTradeFactory, Governable, ProxyAdminDeployer {
    struct DeployClearingHouseParams {
        address clearingHouseLogicAddress;
        address rBaseAddress;
        address insuranceFundAddress;
        address vBaseAddress;
        address UNISWAP_V3_FACTORY_ADDRESS;
        uint24 UNISWAP_V3_DEFAULT_FEE_TIER;
        bytes32 UNISWAP_V3_POOL_BYTE_CODE_HASH;
    }

    function _deployClearingHouse(DeployClearingHouseParams memory params) internal returns (IClearingHouse) {
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                params.clearingHouseLogicAddress,
                address(proxyAdmin),
                abi.encodeWithSelector(
                    IClearingHouse.ClearingHouse__init.selector,
                    address(this), // PoolFactory or RageTradeFactory
                    params.rBaseAddress,
                    params.insuranceFundAddress,
                    params.vBaseAddress,
                    params.UNISWAP_V3_FACTORY_ADDRESS,
                    params.UNISWAP_V3_DEFAULT_FEE_TIER,
                    params.UNISWAP_V3_POOL_BYTE_CODE_HASH
                )
            )
        );

        return IClearingHouse(GoodAddressDeployer.deploy(0, bytecode, _isClearingHouseAddressGood));
    }

    // returns true if most significant hex char of address is "f"
    function _isClearingHouseAddressGood(address addr) private pure returns (bool) {
        return (uint160(addr) >> 156) == 0xf;
    }
}
