//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy.sol';
import { ProxyAdmin } from '../proxy/ProxyAdmin.sol';

import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IRageTradeFactory } from '../interfaces/IRageTradeFactory.sol';

abstract contract VPoolWrapperDeployer is IRageTradeFactory, ProxyAdmin {
    address public vPoolWrapperLogicAddress;

    constructor(address _vPoolWrapperLogicAddress) {
        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    /// @notice Admin method to set latest implementation logic for VPoolWrapper
    /// @param _vPoolWrapperLogicAddress: new logic address
    /// @dev When a new vPoolWrapperLogic is deployed, make sure that the initialize method is called.
    function setVPoolWrapperLogicAddress(address _vPoolWrapperLogicAddress) external onlyOwner {
        if (_vPoolWrapperLogicAddress == address(0)) {
            revert IllegalAddress(address(0));
        }

        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    /// @notice Admin method to upgrade implementation while avoiding human error
    /// @param proxy: A VPoolWrapper proxy contract
    function upgradeVPoolWrapperToLatestLogic(TransparentUpgradeableProxy proxy) public {
        if (_isWrapperAddressGood(address(proxy))) {
            revert ProxyIsNotOfVPoolWrapper(proxy);
        }

        // this public function has onlyOwner modifier
        upgrade(proxy, vPoolWrapperLogicAddress);
    }

    function _deployVPoolWrapper(IVPoolWrapper.InitializeVPoolWrapperParams memory params)
        internal
        returns (IVPoolWrapper)
    {
        bytes memory bytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                address(vPoolWrapperLogicAddress),
                address(this),
                abi.encodeWithSelector(
                    IVPoolWrapper.VPoolWrapper__init.selector,
                    params.clearingHouse,
                    params.vTokenAddress,
                    params.vBase,
                    params.vPool,
                    params.liquidityFeePips,
                    params.protocolFeePips,
                    params.UNISWAP_V3_DEFAULT_FEE_TIER
                )
            )
        );

        return IVPoolWrapper(GoodAddressDeployer.deploy(0, bytecode, _isWrapperAddressGood));
    }

    // returns true if most significant hex char of address is "e"
    function _isWrapperAddressGood(address addr) private pure returns (bool) {
        return (uint160(addr) >> 156) == 0xe;
    }
}
