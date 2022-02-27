//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenLib } from '../libraries/VTokenLib.sol';

import { IVToken } from '../interfaces/IVToken.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

// TODO change to Pool Id Helper test
contract VTokenLibTest is AccountProtocolInfoMock {
    using VTokenLib for IVToken;

    // function vPool(IVToken vToken) external view returns (address) {
    //     return address(vToken.vPool(protocol));
    // }

    // function vPoolWrapper(IVToken vToken) external view returns (address) {
    //     return address(vToken.vPoolWrapper(protocol));
    // }

    // function getVirtualTwapSqrtPrice(IVToken vToken) external view returns (uint160) {
    //     return vToken.getVirtualTwapSqrtPriceX96(protocol);
    // }

    // function getRealTwapSqrtPrice(IVToken vToken) external view returns (uint160) {
    //     return vToken.getRealTwapSqrtPriceX96(protocol);
    // }

    // function getMarginRatio(IVToken vToken, bool isInitialMargin) external view returns (uint16) {
    //     return vToken.getMarginRatio(isInitialMargin, protocol);
    // }
}
