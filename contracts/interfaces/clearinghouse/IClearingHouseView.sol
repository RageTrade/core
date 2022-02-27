//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IVToken } from '../IVToken.sol';
import { IVBase } from '../IVBase.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseView is IClearingHouseStructures {
    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool);

    function getTwapSqrtPricesForSetDuration(IVToken vToken)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128);

    /**
        Account.ProtocolInfo VIEW
     */
    function protocolInfo()
        external
        view
        returns (
            IVBase vBase,
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

    function getAccountInfo(uint256 accountNo)
        external
        view
        returns (
            address owner,
            int256 vBaseBalance,
            DepositTokenView[] memory tokenDeposits,
            VTokenPositionView[] memory tokenPositions
        );

    function getAccountMarketValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin);

    function getAccountNetProfit(uint256 accountNo) external view returns (int256 accountNetProfit);

    function getNetTokenPosition(uint256 accountNo, uint32 vTokenTruncatedAddess)
        external
        view
        returns (int256 netPosition);
}
