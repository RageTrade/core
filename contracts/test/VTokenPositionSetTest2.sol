//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';

import { IVToken } from '../interfaces/IVToken.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

contract VTokenPositionSetTest2 is AccountProtocolInfoMock {
    using Uint32L8ArrayLib for uint32[8];
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using AddressHelper for address;
    using VTokenPositionSet for VTokenPositionSet.Set;

    VTokenPositionSet.Set dummy;

    uint256 accountNo = 123;

    function init(IVToken vToken) external {
        dummy.activate(address(vToken).truncate());
        protocol.pools[address(vToken).truncate()].vToken = vToken;
    }

    function update(IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments, IVToken vToken) external {
        dummy.update(accountNo, balanceAdjustments, address(vToken).truncate(), protocol);
    }

    function swap(IVToken vToken, IClearingHouseStructures.SwapParams memory swapParams) external {
        dummy.swapToken(accountId, address(vToken).truncate(), swapParams, protocol);
    }

    function liquidityChange(
        IVToken vToken,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        dummy.liquidityChange(accountNo, address(vToken).truncate(), liquidityChangeParams, protocol);
    }

    function getAllTokenPositionValue() external view returns (int256) {
        return dummy.getAccountMarketValue(protocol);
    }

    function getRequiredMargin(bool isInititalMargin) external view returns (int256) {
        return dummy.getRequiredMargin(isInititalMargin, protocol);
    }
}
