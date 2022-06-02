// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseEvents is IClearingHouseStructures {
    /// @notice denotes new account creation
    /// @param ownerAddress wallet address of account owner
    /// @param accountId serial number of the account
    event AccountCreated(address indexed ownerAddress, uint256 accountId);

    /// @notice new collateral supported as margin
    /// @param cTokenInfo collateral token info
    event CollateralSettingsUpdated(IERC20 cToken, CollateralSettings cTokenInfo);

    /// @notice maintainance margin ratio of a pool changed
    /// @param poolId id of the rage trade pool
    /// @param settings new settings
    event PoolSettingsUpdated(uint32 poolId, PoolSettings settings);

    /// @notice protocol settings changed
    /// @param liquidationParams liquidation params
    /// @param removeLimitOrderFee fee for remove limit order
    /// @param minimumOrderNotional minimum order notional
    /// @param minRequiredMargin minimum required margin
    event ProtocolSettingsUpdated(
        LiquidationParams liquidationParams,
        uint256 removeLimitOrderFee,
        uint256 minimumOrderNotional,
        uint256 minRequiredMargin
    );

    event PausedUpdated(bool paused);

    /// @notice denotes protocol fee withdrawal from a pool wrapper
    /// @param poolId poolId of token for which fee was withdrawn
    /// @param feeAmount amount of protocol fee which was withdrawn
    event ProtocolFeesWithdrawn(uint32 indexed poolId, uint256 feeAmount);
}
