//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ClearingHouse } from '../ClearingHouse.sol';
import { Account, VTokenPosition } from '../libraries/Account.sol';

contract ClearingHouseTest is ClearingHouse {
    using Account for Account.Info;

    constructor(
        address VPoolFactory,
        address _realBase,
        address _insuranceFundAddress
    ) ClearingHouse(VPoolFactory, _realBase, _insuranceFundAddress) {}

    function getTruncatedTokenAddress(address vTokenAddress) public pure returns (uint32 vTokenTruncatedAddress) {
        return uint32(uint160(vTokenAddress));
    }

    function getTokenAddressInVTokenAddresses(address vTokenAddress)
        external
        view
        returns (address vTokenAddressInVTokenAddresses)
    {
        return vTokenAddresses[getTruncatedTokenAddress(vTokenAddress)];
    }

    function getAccountOwner(uint256 accountNo) external view returns (address owner) {
        return accounts[accountNo].owner;
    }

    function getAccountNumInTokenPositionSet(uint256 accountNo) external view returns (uint256 accountNoInTokenSet) {
        return accounts[accountNo].tokenPositions.accountNo;
    }

    function getAccountDepositBalance(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (uint256 balance)
    {
        balance = accounts[accountNo].tokenDeposits.deposits[getTruncatedTokenAddress(vTokenAddress)];
    }

    function getAccountOpenTokenPosition(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (int256 balance, int256 netTraderPosition)
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            getTruncatedTokenAddress(vTokenAddress)
        ];
        balance = vTokenPosition.balance;
        netTraderPosition = vTokenPosition.netTraderPosition;
    }

    function getAccountValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        return accounts[accountNo].getAccountValueAndRequiredMargin(isInitialMargin, vTokenAddresses, constants);
    }
}
