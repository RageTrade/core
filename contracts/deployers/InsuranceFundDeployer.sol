//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { ProxyAdminDeployer } from './ProxyAdminDeployer.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../interfaces/IInsuranceFund.sol';
import { IVBase } from '../interfaces/IVBase.sol';

abstract contract InsuranceFundDeployer is ProxyAdminDeployer {
    function _deployProxyForInsuranceFund(address insuranceFundLogicAddress) internal returns (IInsuranceFund) {
        return
            IInsuranceFund(
                address(new TransparentUpgradeableProxy(insuranceFundLogicAddress, address(proxyAdmin), hex''))
            );
    }

    function _initializeInsuranceFund(
        IInsuranceFund insuranceFund,
        IVBase vBase,
        IClearingHouse clearingHouse
    ) internal {
        insuranceFund.__InsuranceFund_init(vBase, clearingHouse, 'RageTrade iBase', 'iBase');
    }
}
