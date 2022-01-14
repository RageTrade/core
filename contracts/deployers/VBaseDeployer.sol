//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VBase } from '../tokens/VBase.sol';
import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

abstract contract VBaseDeployer {
    function _deployVBase(address rBase) internal returns (VBase vBase) {
        return
            VBase(
                GoodAddressDeployer.deploy(
                    0,
                    abi.encodePacked(type(VBase).creationCode, abi.encode(rBase)),
                    _isVBaseAddressGood
                )
            );
    }

    // returns true if most significant hex char of address is "d"
    function _isVBaseAddressGood(address addr) private pure returns (bool) {
        return (uint160(addr) >> 156) == 0xd;
    }
}
