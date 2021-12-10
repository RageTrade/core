//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ClearingHouse } from '../ClearingHouse.sol';
import { Account, VTokenPosition } from '../libraries/Account.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

contract ClearingHouseTest is ClearingHouse {
    using Account for Account.Info;
    using VTokenLib for VTokenAddress;

    constructor(
        address VPoolFactory,
        address _realBase,
        address _insuranceFundAddress
    ) ClearingHouse(VPoolFactory, _realBase, _insuranceFundAddress) {}

    // TODO remove
    function getTruncatedTokenAddress(VTokenAddress vTokenAddress) external pure returns (uint32) {
        return vTokenAddress.truncate();
    }

    function getTokenAddressInVTokenAddresses(VTokenAddress vTokenAddress)
        external
        view
        returns (VTokenAddress vTokenAddressInVTokenAddresses)
    {
        return vTokenAddresses[vTokenAddress.truncate()];
    }

    function getAccountOwner(uint256 accountNo) external view returns (address owner) {
        return accounts[accountNo].owner;
    }

    function getAccountNumInTokenPositionSet(uint256 accountNo) external view returns (uint256 accountNoInTokenSet) {
        return accounts[accountNo].tokenPositions.accountNo;
    }

    function getAccountDepositBalance(uint256 accountNo, VTokenAddress vTokenAddress)
        external
        view
        returns (uint256 balance)
    {
        balance = accounts[accountNo].tokenDeposits.deposits[vTokenAddress.truncate()];
    }

    function getAccountOpenTokenPosition(uint256 accountNo, VTokenAddress vTokenAddress)
        external
        view
        returns (int256 balance, int256 netTraderPosition)
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            vTokenAddress.truncate()
        ];
        balance = vTokenPosition.balance;
        netTraderPosition = vTokenPosition.netTraderPosition;
    }

    function getAccountValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        return
            accounts[accountNo].getAccountValueAndRequiredMargin(
                isInitialMargin,
                vTokenAddresses,
                liquidationParams.minRequiredMargin,
                constants
            );
    }
}
