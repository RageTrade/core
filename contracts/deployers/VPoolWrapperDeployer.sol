//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy.sol';
import { ProxyAdmin } from '../proxy/ProxyAdmin.sol';
import { ClearingHouseDeployer } from './ClearingHouseDeployer.sol';

import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IRageTradeFactory } from '../interfaces/IRageTradeFactory.sol';

abstract contract VPoolWrapperDeployer is IRageTradeFactory, ClearingHouseDeployer {
    address public vPoolWrapperLogicAddress;

    constructor(address _vPoolWrapperLogicAddress) {
        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    /// @notice Admin method to set latest implementation logic for VPoolWrapper
    /// @param _vPoolWrapperLogicAddress: new logic address
    /// @dev When a new vPoolWrapperLogic is deployed, make sure that the initialize method is called.
    function setVPoolWrapperLogicAddress(address _vPoolWrapperLogicAddress) external onlyGovernance {
        if (_vPoolWrapperLogicAddress == address(0)) {
            revert IllegalAddress(address(0));
        }

        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    function _deployProxyForVPoolWrapperAndInitialize(IVPoolWrapper.InitializeVPoolWrapperParams memory params)
        internal
        returns (IVPoolWrapper vPoolWrapper)
    {
        return
            IVPoolWrapper(
                address(
                    new TransparentUpgradeableProxy(
                        address(vPoolWrapperLogicAddress),
                        address(proxyAdmin),
                        abi.encodeWithSelector(IVPoolWrapper.VPoolWrapper__init.selector, params)
                    )
                )
            );
    }
}
