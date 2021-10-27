//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

type VToken is address;

library VTokenLib {
    function vPool(VToken vToken) internal pure returns (address) {
        return address(0); // TODO implement
    }
    
    function vPoolWrapper(VToken vToken) internal pure returns (address) {
        return address(0); // TODO implement
    }
    
    function realToken(VToken vToken) internal pure returns (address) {
        return address(0); // TODO implement
    }

    function getVirtualTwapPrice(VToken vToken) internal pure returns(uint160) {
        return 4000000000000000000000;
    }

    function getRealTwapPrice(VToken vToken) internal pure returns(uint160) {
        return 4100000000000000000000;
    }

    function getVirtualTwapTickIndex(VToken vToken) internal pure returns(int24) {
        return 1000;
    }


}
