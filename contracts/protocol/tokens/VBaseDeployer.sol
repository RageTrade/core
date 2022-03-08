//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IVBase } from '../../interfaces/IVBase.sol';

import { GoodAddressDeployer } from '../../libraries/GoodAddressDeployer.sol';

import { VBase } from '../tokens/VBase.sol';

abstract contract VBaseDeployer {
    function _deployVBase(uint8 rcBaseecimals) internal returns (IVBase vBase) {
        return
            IVBase(
                GoodAddressDeployer.deploy(
                    0,
                    abi.encodePacked(type(VBase).creationCode, abi.encode(rcBaseecimals)),
                    _isVBaseAddressGood
                )
            );
    }

    // returns true if most significant hex char of address is "f"
    function _isVBaseAddressGood(address addr) private pure returns (bool) {
        return (uint160(addr) >> 156) == 0xf;
    }
}
