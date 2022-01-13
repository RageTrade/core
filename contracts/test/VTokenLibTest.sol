//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Constants } from '../utils/Constants.sol';

import { AccountStorage } from '../ClearingHouseStorage.sol';

contract VTokenLibTest {
    using VTokenLib for VTokenAddress;

    AccountStorage accountStorage;

    function vPool(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPool(accountStorage));
    }

    function vPoolWrapper(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPoolWrapper(accountStorage));
    }

    function realToken(VTokenAddress vToken) external view returns (address) {
        return address(vToken.realToken());
    }

    function getVirtualTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPriceX96(accountStorage);
    }

    function getRealTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getRealTwapSqrtPriceX96(accountStorage);
    }

    function getMarginRatio(VTokenAddress vToken, bool isInitialMargin) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin, accountStorage);
    }
}
