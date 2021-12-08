//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';
import { Constants } from '../utils/Constants.sol';

contract DepositTokenSetTest {
    using DepositTokenSet for DepositTokenSet.Info;
    using VTokenLib for VTokenAddress;
    using Uint32L8ArrayLib for uint32[8];

    mapping(uint32 => VTokenAddress) vTokenAddresses;

    DepositTokenSet.Info depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(VTokenAddress vTokenAddress) external {
        vTokenAddresses[vTokenAddress.truncate()] = vTokenAddress;
    }

    function cleanDeposits(Constants memory constants) external {
        for (uint256 i = 0; i < depositTokenSet.active.length; i++) {
            uint32 truncatedAddress = depositTokenSet.active[i];
            if (truncatedAddress == 0) break;

            depositTokenSet.decreaseBalance(
                vTokenAddresses[truncatedAddress],
                depositTokenSet.deposits[truncatedAddress],
                constants
            );
        }
        depositTokenSet.decreaseBalance(
            VTokenAddress.wrap(constants.VBASE_ADDRESS),
            depositTokenSet.deposits[uint32(uint160(constants.VBASE_ADDRESS))],
            constants
        );
    }

    function increaseBalance(
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        depositTokenSet.increaseBalance(vTokenAddress, amount, constants);
    }

    function decreaseBalance(
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        depositTokenSet.decreaseBalance(vTokenAddress, amount, constants);
    }

    function getAllDepositAccountMarketValue(Constants memory constants) external view returns (int256 depositValue) {
        return depositTokenSet.getAllDepositAccountMarketValue(vTokenAddresses, constants);
    }

    function getBalance(VTokenAddress vTokenAddress) external view returns (uint256 balance) {
        return depositTokenSet.deposits[vTokenAddress.truncate()];
    }
}
