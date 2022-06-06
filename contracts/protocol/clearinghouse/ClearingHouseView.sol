// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IClearingHouseView } from '../../interfaces/clearinghouse/IClearingHouseView.sol';

import { Account } from '../../libraries/Account.sol';
import { Protocol } from '../../libraries/Protocol.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { Extsload } from '../../utils/Extsload.sol';

abstract contract ClearingHouseView is IClearingHouse, ClearingHouseStorage, Extsload {
    using Account for Account.Info;
    using Protocol for Protocol.Info;

    /// @inheritdoc IClearingHouseView
    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        public
        view
        returns (int256 marketValue, int256 requiredMargin)
    {
        (marketValue, requiredMargin) = accounts[accountId].getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getAccountNetProfit(uint256 accountId) public view returns (int256 accountNetProfit) {
        accountNetProfit = accounts[accountId].getAccountPositionProfits(protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getAccountNetTokenPosition(uint256 accountId, uint32 poolId) public view returns (int256 netPosition) {
        return accounts[accountId].getNetPosition(poolId, protocol);
    }

    /// @inheritdoc IClearingHouseView
    function getRealTwapPriceX128(uint32 poolId) public view returns (uint256 realPriceX128) {
        realPriceX128 = protocol.getRealTwapPriceX128(poolId);
    }

    /// @inheritdoc IClearingHouseView
    function getVirtualTwapPriceX128(uint32 poolId) public view returns (uint256 virtualPriceX128) {
        virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);
    }
}
