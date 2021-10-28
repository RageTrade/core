//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VToken, VTokenLib } from '../libraries/VTokenLib.sol';

contract VTokenLibTest {
    using VTokenLib for VToken;

    function isToken0(VToken vToken) external pure returns (bool) {
        return vToken.isToken0();
    }

    function isToken1(VToken vToken) external pure returns (bool) {
        return vToken.isToken1();
    }

    function vPool(VToken vToken) external pure returns (address) {
        return address(vToken.vPool());
    }

    function vPoolWrapper(VToken vToken) external pure returns (address) {
        return address(vToken.vPoolWrapper());
    }

    function realToken(VToken vToken) external view returns (address) {
        return address(vToken.realToken());
    }

    function getVirtualTwapSqrtPrice(VToken vToken) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPrice();
    }

    function getRealTwapSqrtPrice(VToken vToken) external view returns (uint160) {
        return vToken.getRealTwapSqrtPrice();
    }

    function getVirtualTwapSqrtPrice(VToken vToken, uint32 twapDuration) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPrice(twapDuration);
    }

    function getRealTwapSqrtPrice(VToken vToken, uint32 twapDuration) external view returns (uint160) {
        return vToken.getRealTwapSqrtPrice(twapDuration);
    }

    function getMarginRatio(VToken vToken, bool isInitialMargin) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin);
    }
}
