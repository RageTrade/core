//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityChangeParams, SwapParams } from '../libraries/Account.sol';
import { VTokenAddress } from '../libraries/VTokenLib.sol';

interface IClearingHouse {
    error AccessDenied(address senderAddress);
    error UnsupportedToken(VTokenAddress vTokenAddress);
    error LowNotionalValue(uint256 notionalValue);
    error InvalidLiquidityChangeParameters();
    error InvalidTokenLiquidationParameters();
    error UninitializedToken(uint32 vTokenTruncatedAddress);

    function createAccount() external returns (uint256 newAccountId);

    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 keeperFee);

    function liquidateLiquidityPositions(uint256 accountNo) external returns (int256 keeperFee);

    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external;
}
