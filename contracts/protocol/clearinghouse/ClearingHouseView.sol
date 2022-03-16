// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { Account } from '../../libraries/Account.sol';
import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { Protocol } from '../../libraries/Protocol.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { Extsload } from '../../utils/Extsload.sol';

abstract contract ClearingHouseView is IClearingHouse, ClearingHouseStorage, Extsload {
    using Account for Account.Info;
    using AddressHelper for address;
    using AddressHelper for IVToken;
    using Protocol for Protocol.Info;

    function getTwapPrices(IVToken vToken) external view returns (uint256 realPriceX128, uint256 virtualPriceX128) {
        uint32 poolId = vToken.truncate();
        realPriceX128 = protocol.getRealTwapPriceX128(poolId);
        virtualPriceX128 = protocol.getVirtualTwapPriceX128(poolId);
    }

    function isPoolIdAvailable(uint32 poolId) external view returns (bool) {
        return protocol.pools[poolId].vToken.isZero();
    }

    /**
        Protocol.Info VIEW
     */
    function protocolInfo()
        public
        view
        returns (
            IVQuote vQuote,
            LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        vQuote = protocol.vQuote;
        liquidationParams = protocol.liquidationParams;
        minRequiredMargin = protocol.minRequiredMargin;
        removeLimitOrderFee = protocol.removeLimitOrderFee;
        minimumOrderNotional = protocol.minimumOrderNotional;
    }

    function getPoolInfo(uint32 poolId) public view returns (Pool memory) {
        return protocol.pools[poolId];
    }

    function getCollateralInfo(uint32 collateralId) public view returns (Collateral memory) {
        return protocol.collaterals[collateralId];
    }

    /**
        Account.Info VIEW
     */

    function getAccountInfo(uint256 accountId)
        public
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            CollateralDepositView[] memory collateralDeposits,
            VTokenPositionView[] memory tokenPositions
        )
    {
        return accounts[accountId].getInfo(protocol);
    }

    // isInitialMargin true is initial margin, false is maintainance margin
    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        public
        view
        returns (int256 marketValue, int256 requiredMargin)
    {
        (marketValue, requiredMargin) = accounts[accountId].getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    function getAccountNetProfit(uint256 accountId) public view returns (int256 accountNetProfit) {
        accountNetProfit = accounts[accountId].getAccountPositionProfits(protocol);
    }

    function getNetTokenPosition(uint256 accountId, uint32 poolId) public view returns (int256 netPosition) {
        return accounts[accountId].getNetPosition(poolId, protocol);
    }
}
