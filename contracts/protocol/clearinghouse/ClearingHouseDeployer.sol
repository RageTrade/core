//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { ProxyAdminDeployer } from '../../utils/ProxyAdminDeployer.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IOracle } from '../../interfaces/IOracle.sol';

/// @notice Manages deployment for ClearingHouseProxy
/// @dev ClearingHouse proxy is deployed only once
abstract contract ClearingHouseDeployer is ProxyAdminDeployer {
    struct DeployClearingHouseParams {
        address clearingHouseLogicAddress;
        IERC20 cBase;
        IOracle cBaseOracle;
        IInsuranceFund insuranceFund;
        IERC20 vBase;
        IOracle nativeOracle;
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
                            IClearingHouse.__ClearingHouse_init.selector,
                            address(this), // RageTradeFactory
                            params.cBase,
                            params.cBaseOracle,
                            params.insuranceFund,
                            params.vBase,
                            params.nativeOracle
                        )
                    )
                )
            );
    }
}
