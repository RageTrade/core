//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VToken, vTokenLib } from '../libraries/vTokenLib.sol';

contract vTokenLibTest {
    function isToken0(address vToken) external pure returns (bool) {
        return vTokenLib.isToken0(VToken.wrap(vToken));
    }

    function isToken1(address vToken) external pure returns (bool) {
        return vTokenLib.isToken1(VToken.wrap(vToken));
    }

    function vPool(address vToken) external pure returns (address) {
        return vTokenLib.vPool(VToken.wrap(vToken));
    }

    function vPoolWrapper(address vToken) external pure returns (address) {
        return vTokenLib.vPoolWrapper(VToken.wrap(vToken));
    }

    function realToken(address vToken) external view returns (address) {
        return vTokenLib.realToken(VToken.wrap(vToken));
    }

    function getVirtualTwapSqrtPrice(address vToken) external view returns (uint160) {
        return vTokenLib.getVirtualTwapSqrtPrice(VToken.wrap(vToken));
    }

    function getRealTwapSqrtPrice(address vToken) external view returns (uint160) {
        return vTokenLib.getRealTwapSqrtPrice(VToken.wrap(vToken));
    }

    function getVirtualTwapSqrtPrice(address vToken, uint32 twapDuration) external view returns (uint160) {
        return vTokenLib.getVirtualTwapSqrtPrice(VToken.wrap(vToken), twapDuration);
    }

    function getRealTwapSqrtPrice(address vToken, uint32 twapDuration) external view returns (uint160) {
        return vTokenLib.getRealTwapSqrtPrice(VToken.wrap(vToken), twapDuration);
    }

    function getMarginRatio(address vToken, bool isInitialMargin) external view returns (uint16) {
        return vTokenLib.getMarginRatio(VToken.wrap(vToken), isInitialMargin);
    }
}
