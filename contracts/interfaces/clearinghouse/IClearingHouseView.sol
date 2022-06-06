// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';
import { IExtsload } from '../IExtsload.sol';
import { IVQuote } from '../IVQuote.sol';

interface IClearingHouseView is IClearingHouseStructures, IExtsload {
    /// @notice Gets details about account id
    /// @param accountId the account id
    /// @return owner address of the account creator
    /// @return vQuoteBalance the vQuote balance of the account
    /// @return collateralDeposits the collateral deposits of the account
    /// @return tokenPositions the token positions of the account along with liquidity positions
    function getAccountInfo(uint256 accountId)
        external
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            CollateralDepositView[] memory collateralDeposits,
            VTokenPositionView[] memory tokenPositions
        );

    /// @notice Gets the market value and required margin of an account
    /// @dev This method can be used to check if an account is under water or not.
    ///     If accountMarketValue < requiredMargin then liquidation can take place.
    /// @param accountId the account id
    /// @param isInitialMargin true is initial margin, false is maintainance margin
    /// @return accountMarketValue the market value of the account, due to collateral and positions
    /// @return requiredMargin margin needed due to positions
    function getAccountMarketValueAndRequiredMargin(uint256 accountId, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin);

    /// @notice Gets the net profit of an account
    /// @param accountId the account id
    /// @return accountNetProfit the net profit of the account
    function getAccountNetProfit(uint256 accountId) external view returns (int256 accountNetProfit);

    /// @notice Gets the net position of an account
    /// @param accountId the account id
    /// @param poolId the id of the pool (vETH, ... etc)
    /// @return netPosition the net position of the account
    function getAccountNetTokenPosition(uint256 accountId, uint32 poolId) external view returns (int256 netPosition);

    /// @notice Gets the info about a supported collateral in the protocol
    /// @param collateralId the id of the collateral
    /// @return collateral the Collateral struct
    function getCollateralInfo(uint32 collateralId) external view returns (Collateral memory);

    /// @notice Gets the real twap price from the respective oracle of the given poolId
    /// @param poolId the id of the pool
    /// @return realPriceX128 the real price of the pool
    function getRealTwapPriceX128(uint32 poolId) external view returns (uint256 realPriceX128);

    /// @notice Gets the virtual twap price from the respective oracle of the given poolId
    /// @param poolId the id of the pool
    /// @return virtualPriceX128 the virtual price of the pool
    function getVirtualTwapPriceX128(uint32 poolId) external view returns (uint256 virtualPriceX128);
}
