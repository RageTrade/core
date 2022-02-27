//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseEvents is IClearingHouseStructures {
    // TODO this is not being used. use it somewhere?
    /// @notice new rage trade pool supported
    /// @param poolId address of vToken
    event NewVTokenSupported(uint32 poolId);

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
}
