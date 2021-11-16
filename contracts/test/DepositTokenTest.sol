//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VBASE_ADDRESS } from '../Constants.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';

contract DepositTokenSetTest {
    using DepositTokenSet for DepositTokenSet.Info;

    using Uint32L8ArrayLib for uint32[8];
    mapping(uint32 => address) vTokenAddresses;

    DepositTokenSet.Info depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(address vTokenAddress) external {
        vTokenAddresses[VTokenPositionSet.truncate(vTokenAddress)] = vTokenAddress;
    }

    function increaseBalance(address vTokenAddress, uint256 amount) external {
        depositTokenSet.increaseBalance(vTokenAddress, amount);
    }

    function decreaseBalance(address vTokenAddress, uint256 amount) external {
        depositTokenSet.decreaseBalance(vTokenAddress, amount);
    }

    function getAllDepositAccountMarketValue() external view {
        depositTokenSet.getAllDepositAccountMarketValue(vTokenAddresses);
    }

    function getBalance(address vTokenAddress) external view returns (uint256 balance) {
        return depositTokenSet.deposits[VTokenPositionSet.truncate(vTokenAddress)];
    }
}
