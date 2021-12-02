//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityChangeParams, SwapParams } from '../libraries/Account.sol';

interface IClearingHouse {
    error AccessDenied(address senderAddress);
    error UnsupportedToken(address vTokenAddress);
    error LowNotionalValue(uint256 notionalValue);
    error InvalidLiquidityChangeParameters();
    error UninitializedToken(uint32 vTokenTruncatedAddress);

    function createAccount() external;

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
    ) external;

    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external;

    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external;

    function liquidateLiquidityPositions(uint256 accountNo) external;

    function liquidateTokenPosition(uint256 accountNo, uint32 vTokenTruncatedAddress) external;
}
