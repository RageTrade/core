//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { AccountStorage } from '../protocol/clearinghouse/ClearingHouseStorage.sol';

import { AccountStorageMock } from './mocks/AccountStorageMock.sol';

contract VTokenLibTest is AccountStorageMock {
    using VTokenLib for VTokenAddress;

    function vPool(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPool(accountStorage));
    }

    function vPoolWrapper(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPoolWrapper(accountStorage));
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
