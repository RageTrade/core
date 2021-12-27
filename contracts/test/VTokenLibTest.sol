//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Constants } from '../utils/Constants.sol';

contract VTokenLibTest {
    using VTokenLib for VTokenAddress;

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
