//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { ProxyAdminDeployer } from './ProxyAdminDeployer.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../interfaces/IInsuranceFund.sol';

abstract contract InsuranceFundDeployer is ProxyAdminDeployer {
    function _deployProxyForInsuranceFund(address insuranceFundLogicAddress) internal returns (IInsuranceFund) {
        return
            IInsuranceFund(
                address(new TransparentUpgradeableProxy(insuranceFundLogicAddress, address(proxyAdmin), hex''))
            );
    }

    function _initializeInsuranceFund(
        IInsuranceFund insuranceFund,
        IERC20 rBase,
        IClearingHouse clearingHouse
    ) internal {
        insuranceFund.__InsuranceFund_init(rBase, clearingHouse, 'RageTrade iBase', 'iBase');
    }
}
