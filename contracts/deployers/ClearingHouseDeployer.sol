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
    }

    function _deployProxyForClearingHouseAndInitialize(DeployClearingHouseParams memory params)
        internal
        returns (IClearingHouse)
    {
        return
            IClearingHouse(
                address(
                    new TransparentUpgradeableProxy(
                        params.clearingHouseLogicAddress,
                        address(proxyAdmin),
                        abi.encodeWithSelector(
                            IClearingHouse.ClearingHouse__init.selector,
                            address(this), // RageTradeFactory
                            params.rBaseAddress,
                            params.insuranceFundAddress,
                            params.vBaseAddress
                        )
                    )
                )
            );
    }
}
