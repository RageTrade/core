//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { VTokenLib } from '../libraries/VTokenLib.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { CTokenDepositSet } from '../libraries/CTokenDepositSet.sol';

import { IVToken } from '../interfaces/IVToken.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract DepositTokenSetTest is AccountProtocolInfoMock {
    using CTokenDepositSet for CTokenDepositSet.Info;
    using AddressHelper for address;
    using AddressHelper for IERC20;
    using Uint32L8ArrayLib for uint32[8];

    CTokenDepositSet.Info depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor(address _rBase) {
        wrapper = new VPoolWrapperMock();
        protocol.rBase = IERC20(_rBase);
    }

    function initVToken(address vToken) external {
        protocol.vTokens[vToken.truncate()] = IVToken(vToken);
    }

    function init(
        IERC20 cToken,
        IOracle oracle,
        uint32 twapDuration
    ) external {
        IClearingHouseStructures.Collateral memory collateral = IClearingHouseStructures.Collateral(
            cToken,
            IClearingHouseStructures.CollateralSettings(oracle, twapDuration, true)
        );
        protocol.cTokens[collateral.token.truncate()] = collateral;
    }

    function cleanDeposits() external {
        for (uint256 i = 0; i < depositTokenSet.active.length; i++) {
            uint32 truncatedAddress = depositTokenSet.active[i];
            if (truncatedAddress == 0) break;

            depositTokenSet.decreaseBalance(
                address(protocol.cTokens[truncatedAddress].token),
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
