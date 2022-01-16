//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

contract VTokenPositionSetTest2 is AccountProtocolInfoMock {
    using Uint32L8ArrayLib for uint32[8];
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;

    mapping(uint32 => VTokenAddress) vTokenAddresses;
    VTokenPositionSet.Set dummy;

    function init(VTokenAddress vTokenAddress) external {
        VTokenPositionSet.activate(dummy, vTokenAddress);
        vTokenAddresses[vTokenAddress.truncate()] = vTokenAddress;
    }

    function update(Account.BalanceAdjustments memory balanceAdjustments, VTokenAddress vTokenAddress) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress, protocol);
    }

    function liquidityChange(
        VTokenAddress vTokenAddress,
        LiquidityPositionSet.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        VTokenPositionSet.liquidityChange(dummy, vTokenAddress, liquidityChangeParams, protocol);
    }

    function getAllTokenPositionValue() external view returns (int256) {
        return VTokenPositionSet.getAccountMarketValue(dummy, vTokenAddresses, protocol);
    }

    function getRequiredMargin(bool isInititalMargin) external view returns (int256) {
        return VTokenPositionSet.getRequiredMargin(dummy, isInititalMargin, vTokenAddresses, protocol);
    }
}
