//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';
import { VTokenLib } from '../libraries/VTokenLib.sol';

import { IVToken } from '../interfaces/IVToken.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

contract VTokenPositionSetTest2 is AccountProtocolInfoMock {
    using Uint32L8ArrayLib for uint32[8];
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for IVToken;
    using VTokenPositionSet for VTokenPositionSet.Set;

    mapping(uint32 => IVToken) vTokens;
    VTokenPositionSet.Set dummy;

    function init(IVToken vToken) external {
        VTokenPositionSet.activate(dummy, vToken);
        vTokens[vToken.truncate()] = vToken;
    }

    function update(IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments, IVToken vToken) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vToken, protocol);
    }

    function liquidityChange(
        IVToken vToken,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        VTokenPositionSet.liquidityChange(dummy, vToken, liquidityChangeParams, protocol);
    }

    function getAllTokenPositionValue() external view returns (int256) {
        return VTokenPositionSet.getAccountMarketValue(dummy, vTokens, protocol);
    }

    function getRequiredMargin(bool isInititalMargin) external view returns (int256) {
        return VTokenPositionSet.getRequiredMargin(dummy, isInititalMargin, vTokens, protocol);
    }
}
