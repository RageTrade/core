//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { console } from 'hardhat/console.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VBASE_ADDRESS } from '../Constants.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';

import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract VTokenPositionSetTest {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using Uint32L8ArrayLib for uint32[8];

    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(address vTokenAddress) external {
        VTokenPositionSet.activate(dummy, VBASE_ADDRESS);
        VTokenPositionSet.activate(dummy, vTokenAddress);
    }

    function update(Account.BalanceAdjustments memory balanceAdjustments, address vTokenAddress) external {
        VTokenPositionSet.update(balanceAdjustments, dummy, vTokenAddress);
    }

    function realizeFundingPaymentToAccount(address vTokenAddress) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vTokenAddress, wrapper);
    }

    function getPositionDetails(address vTokenAddress)
        external
        view
        returns (
            int256,
            int256,
            int256
        )
    {
        VTokenPosition.Position storage pos = dummy.positions[VTokenPositionSet.truncate(vTokenAddress)];
        return (pos.balance, pos.sumAChkpt, pos.netTraderPosition);
    }

    function abs(int256 x) external pure returns (int256) {
        return VTokenPositionSet.abs(x);
    }
}
