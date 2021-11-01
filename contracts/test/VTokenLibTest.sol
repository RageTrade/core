//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenType, VTokenLib } from '../libraries/VTokenLib.sol';

contract VTokenLibTest {
    using VTokenLib for VTokenType;

    function isToken0(VTokenType vToken) external pure returns (bool) {
        return vToken.isToken0();
    }

    function isToken1(VTokenType vToken) external pure returns (bool) {
        return vToken.isToken1();
    }

    function vPool(VTokenType vToken) external pure returns (address) {
        return address(vToken.vPool());
    }

    function vPoolWrapper(VTokenType vToken) external pure returns (address) {
        return address(vToken.vPoolWrapper());
    }

    function realToken(VTokenType vToken) external view returns (address) {
        return address(vToken.realToken());
    }

    function getVirtualTwapSqrtPrice(VTokenType vToken) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPrice();
    }

    function getRealTwapSqrtPrice(VTokenType vToken) external view returns (uint160) {
        return vToken.getRealTwapSqrtPrice();
    }

    function getMarginRatio(VTokenType vToken, bool isInitialMargin) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin);
    }
}
