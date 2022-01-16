//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

contract VTokenLibTest is AccountProtocolInfoMock {
    using VTokenLib for VTokenAddress;

    function vPool(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPool(protocol));
    }

    function vPoolWrapper(VTokenAddress vToken) external view returns (address) {
        return address(vToken.vPoolWrapper(protocol));
    }

    function getVirtualTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getVirtualTwapSqrtPriceX96(protocol);
    }

    function getRealTwapSqrtPrice(VTokenAddress vToken) external view returns (uint160) {
        return vToken.getRealTwapSqrtPriceX96(protocol);
    }

    function getMarginRatio(VTokenAddress vToken, bool isInitialMargin) external view returns (uint16) {
        return vToken.getMarginRatio(isInitialMargin, protocol);
    }
}
