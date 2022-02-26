//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IVBase } from '../../interfaces/IVBase.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { Account } from '../../libraries/Account.sol';
import { VTokenLib } from '../../libraries/VTokenLib.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { Extsload } from '../../utils/Extsload.sol';

abstract contract ClearingHouseView is IClearingHouse, ClearingHouseStorage, Extsload {
    using Account for Account.UserInfo;
    using VTokenLib for IVToken;

    function getTwapSqrtPricesForSetDuration(IVToken vToken)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        realPriceX128 = vToken.getRealTwapPriceX128(protocol);
        virtualPriceX128 = vToken.getVirtualTwapPriceX128(protocol);
    }

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool) {
        return protocol.vTokens[truncated].eq(address(0));
    }

    /**
        Account.ProtocolInfo VIEW
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

    function pools(IVToken vToken) public view returns (RageTradePool memory) {
        return protocol.pools[vToken];
    }

    function cTokens(uint32 cTokenId) public view returns (Collateral memory) {
        return protocol.cTokens[cTokenId];
    }

    function vTokens(uint32 vTokenAddressTruncated) public view returns (IVToken) {
        return protocol.vTokens[vTokenAddressTruncated];
    }

    /**
        Account.UserInfo VIEW
     */

    function getAccountView(uint256 accountNo)
        public
        view
        returns (
            address owner,
            int256 vBaseBalance,
            DepositTokenView[] memory tokenDeposits,
            VTokenPositionView[] memory tokenPositions
        )
    {
        return accounts[accountNo].getView(protocol);
    }

    // isInitialMargin true is initial margin, false is maintainance margin
    function getAccountMarketValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        public
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        (accountMarketValue, requiredMargin) = accounts[accountNo].getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
    }

    function getAccountNetProfit(uint256 accountNo) public view returns (int256 accountNetProfit) {
        accountNetProfit = accounts[accountNo].getAccountPositionProfits(protocol);
    }
}
