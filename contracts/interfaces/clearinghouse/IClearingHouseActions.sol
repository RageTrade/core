//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseActions is IClearingHouseStructures {
    /// @notice creates a new account and adds it to the accounts map
    /// @return newAccountId - serial number of the new account created
    function createAccount() external returns (uint256 newAccountId);

    /// @notice deposits 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to deposit
    /// @param amount amount of token to deposit
    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    /// @notice creates a new account and deposits 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param vTokenTruncatedAddress truncated address of token to deposit
    /// @param amount amount of token to deposit
    /// @return newAccountId - serial number of the new account created
    function createAccountAndAddMargin(uint32 vTokenTruncatedAddress, uint256 amount)
        external
        returns (uint256 newAccountId);

    /// @notice withdraws 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param amount amount of token to withdraw
    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    /// @notice withdraws 'amount' of base token from the profit made
    /// @param accountNo account number
    /// @param amount amount of token to withdraw
    function updateProfit(uint256 accountNo, int256 amount) external;

    /// @notice swaps token associated with 'vTokenTruncatedAddress' by 'amount' (Long if amount>0 else Short)
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param swapParams swap parameters
    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    /// @notice updates range order of token associated with 'vTokenTruncatedAddress' by 'liquidityDelta' (Adds if amount>0 else Removes)
    /// @notice also can be used to update limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidityChangeParams liquidity change parameters
    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    /// @notice keeper call to remove a limit order
    /// @dev checks the position of current price relative to limit order and checks limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param tickLower liquidity change parameters
    /// @param tickUpper liquidity change parameters
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external;

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountNo account number
    function liquidateLiquidityPositions(uint256 accountNo) external;

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param liquidatorAccountNo liquidator account number
    /// @param targetAccountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidationBps fraction of the token position to be transferred in BPS
    /// @return liquidatorBalanceAdjustments - balance changes in liquidator base and token balance and net token position
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 targetAccountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments);

    /// @notice keeper call to remove a limit order
    /// @dev checks the position of current price relative to limit order and checks limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param tickLower liquidity change parameters
    /// @param tickUpper liquidity change parameters
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return keeperFee : amount of fees paid to caller
    function removeLimitOrderWithGasClaim(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) external returns (uint256 keeperFee);

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountNo account number
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return keeperFee : amount of fees paid to caller
    function liquidateLiquidityPositionsWithGasClaim(uint256 accountNo, uint256 gasComputationUnitsClaim)
        external
        returns (int256 keeperFee);

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param liquidatorAccountNo liquidator account number
    /// @param targetAccountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidationBps fraction of the token position to be transferred in BPS
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return liquidatorBalanceAdjustments - balance changes in liquidator base and token balance and net token position
    function liquidateTokenPositionWithGasClaim(
        uint256 liquidatorAccountNo,
        uint256 targetAccountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments);
}
