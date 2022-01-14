//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy.sol';

interface IRageTradeFactory {
    /// @notice error to denote an address that is forbidden
    /// @param addr the address that is forbidden
    error IllegalAddress(address addr);

    error ProxyIsNotOfVPoolWrapper(TransparentUpgradeableProxy proxy);

    error ProxyIsNotOfClearingHouse(TransparentUpgradeableProxy proxy);
}
