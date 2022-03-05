//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IVBase } from '../../interfaces/IVBase.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { Account } from '../../libraries/Account.sol';
import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { Protocol } from '../../libraries/Protocol.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { Extsload } from '../../utils/Extsload.sol';

abstract contract ClearingHouseView is IClearingHouse, ClearingHouseStorage, Extsload {
    using Account for Account.Info;
    using AddressHelper for address;
    using Protocol for Protocol.Info;

    // TODO rename this to getTwapSqrtPrices
    function getTwapSqrtPricesForSetDuration(IVToken vToken)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        uint32 poolId = address(vToken).truncate();
        realPriceX128 = protocol.getRealTwapPriceX128For(poolId);
        virtualPriceX128 = protocol.getVirtualTwapPriceX128For(poolId);
    }

    function isVTokenAddressAvailable(uint32 poolId) external view returns (bool) {
        return address(protocol.pools[poolId].vToken).isZero() && poolId != address(protocol.vBase).truncate();
    }

    /**
        Protocol.Info VIEW
     */
    function protocolInfo()
        public
        view
        returns (
            IVBase vBase,
            LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        vBase = protocol.vBase;
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
            int256 vBaseBalance,
            DepositTokenView[] memory tokenDeposits,
            VTokenPositionView[] memory tokenPositions
        )
    {
        return accounts[accountId].getInfo(protocol);
    }

    // isInitialMargin true is initial margin, false is maintainance margin
    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        public
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        (accountMarketValue, requiredMargin) = accounts[accountId].getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
    }

    function getAccountNetProfit(uint256 accountId) public view returns (int256 accountNetProfit) {
        accountNetProfit = accounts[accountId].getAccountPositionProfits(protocol);
    }

    function getNetTokenPosition(uint256 accountId, uint32 poolId) public view returns (int256 netPosition) {
        return accounts[accountId].getNetPosition(poolId, protocol);
    }
}
