//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

contract VTokenLibTest {
    using VTokenLib for VTokenAddress;

    function isToken0(VTokenAddress vToken) external pure returns (bool) {
        return vToken.isToken0();
    }

    function isToken1(VTokenAddress vToken) external pure returns (bool) {
        return vToken.isToken1();
    }

    function flip(
        VTokenAddress vToken,
        int256 amount0,
        int256 amount1
    ) external pure returns (int256 baseAmount, int256 vTokenAmount) {
        return vToken.flip(amount0, amount1);
    }

    function vPool(VTokenAddress vToken) external pure returns (address) {
        return address(vToken.vPool());
    }

    function vPoolWrapper(VTokenAddress vToken) external pure returns (address) {
        return address(vToken.vPoolWrapper());
    }

    function realToken(VTokenAddress vToken) external view returns (address) {
        return address(vToken.realToken());
    }

    function getVirtualTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPrice();
    }

    function getRealTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getRealTwapSqrtPrice();
    }

    function getMarginRatio(VTokenAddress vToken, bool isInitialMargin) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin);
    }
}
