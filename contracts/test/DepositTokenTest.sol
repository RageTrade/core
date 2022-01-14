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
import { RTokenLib } from '../libraries/RTokenLib.sol';
import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';
import { AccountStorage } from '../ClearingHouseStorage.sol';

import { AccountStorage } from '../ClearingHouseStorage.sol';
import { AccountStorageMock } from './mocks/AccountStorageMock.sol';

contract DepositTokenSetTest is AccountStorageMock {
    using DepositTokenSet for DepositTokenSet.Info;
    using RTokenLib for RTokenLib.RToken;
    using RTokenLib for address;
    using Uint32L8ArrayLib for uint32[8];

    DepositTokenSet.Info depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function initVToken(address vTokenAddress) external {
        accountStorage.vTokenAddresses[vTokenAddress.truncate()] = VTokenAddress.wrap(vTokenAddress);
    }

    function init(
        address rTokenAddress,
        address oracleAddress,
        uint32 twapDuration
    ) external {
        RTokenLib.RToken memory token = RTokenLib.RToken(rTokenAddress, oracleAddress, twapDuration);
        accountStorage.realTokens[token.tokenAddress.truncate()] = token;
    }

    function cleanDeposits() external {
        for (uint256 i = 0; i < depositTokenSet.active.length; i++) {
            uint32 truncatedAddress = depositTokenSet.active[i];
            if (truncatedAddress == 0) break;

            depositTokenSet.decreaseBalance(
                accountStorage.realTokens[truncatedAddress].tokenAddress,
                depositTokenSet.deposits[truncatedAddress]
            );
        }
    }

    function increaseBalance(address realTokenAddress, uint256 amount) external {
        depositTokenSet.increaseBalance(realTokenAddress, amount);
    }

    function decreaseBalance(address realTokenAddress, uint256 amount) external {
        depositTokenSet.decreaseBalance(realTokenAddress, amount);
    }

    function getAllDepositAccountMarketValue() external view returns (int256 depositValue) {
        return depositTokenSet.getAllDepositAccountMarketValue(accountStorage);
    }

    function getBalance(address realTokenAddress) external view returns (uint256 balance) {
        return depositTokenSet.deposits[realTokenAddress.truncate()];
    }
}
