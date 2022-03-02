//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseEvents is IClearingHouseStructures {
    /// @notice denotes new account creation
    /// @param ownerAddress wallet address of account owner
    /// @param accountNo serial number of the account
    event AccountCreated(address indexed ownerAddress, uint256 accountNo);

    /// @notice denotes deposit of margin
    /// @param accountNo serial number of the account
    /// @param collateralId token in which margin is deposited
    /// @param amount amount of tokens deposited
    event DepositMargin(uint256 indexed accountNo, uint32 indexed collateralId, uint256 amount);

    /// @notice denotes withdrawal of margin
    /// @param accountNo serial number of the account
    /// @param collateralId token in which margin is withdrawn
    /// @param amount amount of tokens withdrawn
    event WithdrawMargin(uint256 indexed accountNo, uint32 indexed collateralId, uint256 amount);

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
}
