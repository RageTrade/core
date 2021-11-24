//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LimitOrderType } from '../libraries/LiquidityPosition.sol';

interface IClearingHouse {
    event AccountCreated(address ownerAddress, uint256 accountNo);
    event DepositMargin(uint256 accountNo, uint32 truncatedTokenAddress, uint256 amount);
    event WithdrawMargin(uint256 accountNo, uint32 truncatedTokenAddress, uint256 amount);
    event WithdrawProfit(uint256 accountNo, int256 amount);

    event TokenPositionChange(
        uint256 accountNo,
        uint32 truncatedTokenAddress,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );
    event LiquidityChange(
        uint256 accountNo,
        uint32 truncatedTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        LimitOrderType limitOrderType,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );
    event LiquidateRanges(uint256 accountNo, uint256 liquidationFee);
    event LiquidateTokenPosition(uint256 accountNo,  uint32 truncatedTokenAddress, uint256 notionalClosed, uint256 liquidationFee);

    event FundingPayment(uint256 accountNo, uint32 truncatedTokenAddress, uint48 rangePositionIndex, int256 amount);
    event LiquidityFee(uint256 accountNo, uint32 truncatedTokenAddress, uint256 rangePositionIndex, int256 amount);
}
