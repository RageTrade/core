//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { Constants } from '../utils/Constants.sol';

contract VTokenPositionSetTest2 {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using Uint32L8ArrayLib for uint32[8];
    mapping(uint32 => address) vTokenAddresses;
    VTokenPositionSet.Set dummy;

    function init(address vTokenAddress) external {
        VTokenPositionSet.activate(dummy, vTokenAddress);
        vTokenAddresses[VTokenPositionSet.truncate(vTokenAddress)] = vTokenAddress;
    }

    function update(
        Account.BalanceAdjustments memory balanceAdjustments,
        address vTokenAddress,
        Constants memory constants
    ) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress, constants);
    }

    function liquidityChange(
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        Constants memory constants
    ) external {
        VTokenPositionSet.liquidityChange(dummy, vTokenAddress, liquidityChangeParams, constants);
    }

    function getAllTokenPositionValue(Constants memory constants) external view returns (int256) {
        return VTokenPositionSet.getAccountMarketValue(dummy, vTokenAddresses, constants);
    }

    function getRequiredMargin(bool isInititalMargin, Constants memory constants) external view returns (int256) {
        return VTokenPositionSet.getRequiredMargin(dummy, isInititalMargin, vTokenAddresses, constants);
    }
}
