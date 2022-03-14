// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IVToken } from '../IVToken.sol';
import { IVQuote } from '../IVQuote.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseView is IClearingHouseStructures {
    function isPoolIdAvailable(uint32 truncated) external view returns (bool);

    function getTwapPrices(IVToken vToken) external view returns (uint256 realPriceX128, uint256 virtualPriceX128);

    /**
        Protocol.Info VIEW
     */
    function protocolInfo()
        external
        view
        returns (
            IVQuote vQuote,
            LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        );

    function getPoolInfo(uint32 poolId) external view returns (Pool memory);

    function getCollateralInfo(uint32 collateralId) external view returns (Collateral memory);

    /**
        Account.UserInfo VIEW
     */

    function getAccountInfo(uint256 accountId)
        external
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            CollateralDepositView[] memory collateralDeposits,
            VTokenPositionView[] memory tokenPositions
        );

    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin);

    function getAccountNetProfit(uint256 accountId) external view returns (int256 accountNetProfit);

    function getNetTokenPosition(uint256 accountId, uint32 vTokenTruncatedAddess)
        external
        view
        returns (int256 netPosition);
}
