//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Constants } from '../Constants.sol';

contract VTokenLibTest {
    using VTokenLib for VTokenAddress;

    function isToken0(VTokenAddress vToken, Constants memory constants) external pure returns (bool) {
        return vToken.isToken0(constants);
    }

    function isToken1(VTokenAddress vToken, Constants memory constants) external pure returns (bool) {
        return vToken.isToken1(constants);
    }

    function flip(
        VTokenAddress vToken,
        int256 amount0,
        int256 amount1,
        Constants memory constants
    ) external pure returns (int256 baseAmount, int256 vTokenAmount) {
        return vToken.flip(amount0, amount1, constants);
    }

    function vPool(VTokenAddress vToken, Constants memory constants) external pure returns (address) {
        return address(vToken.vPool(constants));
    }

    function vPoolWrapper(VTokenAddress vToken, Constants memory constants) external pure returns (address) {
        return address(vToken.vPoolWrapper(constants));
    }

    function realToken(VTokenAddress vToken) external view returns (address) {
        return address(vToken.realToken());
    }

    function getVirtualTwapSqrtPrice(VTokenAddress vToken, Constants memory constants) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPriceX96(constants);
    }

    function getRealTwapSqrtPrice(VTokenAddress vToken, Constants memory constants) external view returns (uint160) {
        return vToken.getRealTwapSqrtPriceX96(constants);
    }

    function getMarginRatio(
        VTokenAddress vToken,
        bool isInitialMargin,
        Constants memory constants
    ) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin, constants);
    }
}
