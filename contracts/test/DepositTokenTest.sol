//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { VTokenLib } from '../libraries/VTokenLib.sol';
import { RTokenLib } from '../libraries/RTokenLib.sol';
import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';

import { IVToken } from '../interfaces/IVToken.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract DepositTokenSetTest is AccountProtocolInfoMock {
    using DepositTokenSet for DepositTokenSet.Info;
    using RTokenLib for RTokenLib.RToken;
    using RTokenLib for address;
    using Uint32L8ArrayLib for uint32[8];

    DepositTokenSet.Info depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor(address _rBase) {
        wrapper = new VPoolWrapperMock();
        protocol.rBase = IERC20(_rBase);
    }

    function initVToken(address vToken) external {
        protocol.vTokens[vToken.truncate()] = IVToken(vToken);
    }

    function init(
        address rTokenAddress,
        address oracleAddress,
        uint32 twapDuration
    ) external {
        RTokenLib.RToken memory token = RTokenLib.RToken(rTokenAddress, oracleAddress, twapDuration);
        protocol.rTokens[token.tokenAddress.truncate()] = token;
    }

    function cleanDeposits() external {
        for (uint256 i = 0; i < depositTokenSet.active.length; i++) {
            uint32 truncatedAddress = depositTokenSet.active[i];
            if (truncatedAddress == 0) break;

            depositTokenSet.decreaseBalance(
                protocol.rTokens[truncatedAddress].tokenAddress,
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
        return depositTokenSet.getAllDepositAccountMarketValue(protocol);
    }

    function getBalance(address realTokenAddress) external view returns (uint256 balance) {
        return depositTokenSet.deposits[realTokenAddress.truncate()];
    }
}
