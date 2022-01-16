//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPosition } from '../libraries/VTokenPosition.sol';

import { IVToken } from '../interfaces/IVToken.sol';

import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract VTokenPositionTest {
    using VTokenPosition for VTokenPosition.Position;

    uint256 num;
    mapping(uint256 => VTokenPosition.Position) internal dummys;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(
        int256 _balance,
        int256 _netTraderPosition,
        int256 _sumAChkpt
    ) external {
        VTokenPosition.Position storage dummy = dummys[num++];
        dummy.balance = _balance;
        dummy.netTraderPosition = _netTraderPosition;
        dummy.sumAX128Ckpt = _sumAChkpt;
    }

    function marketValue(uint256 price) external view returns (int256 value) {
        return dummys[0].marketValue(price, wrapper);
    }

    function riskSide() external view returns (uint8) {
        return uint8(dummys[0].riskSide());
    }

    function unrealizedFundingPayment() external view returns (int256) {
        return dummys[0].unrealizedFundingPayment(wrapper);
    }
}
