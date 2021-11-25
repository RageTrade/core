//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityChangeParams } from '../libraries/Account.sol';

interface IClearingHouse {
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

    function swapTokenAmount(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vTokenAmount
    ) external;

    function swapTokenNotional(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vBaseAmount
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
