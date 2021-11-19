//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account, LiquidityChangeParams } from './libraries/Account.sol';
import { LimitOrderType } from './libraries/LiquidityPosition.sol';
import { BridgeFactoryAndHouse } from './BridgeFactoryAndHouse.sol';

contract ClearingHouse is BridgeFactoryAndHouse {
    using Account for Account.Info;
    mapping(address => bool) public supportedVTokens;
    mapping(address => bool) public supportedDeposits;

    uint256 public numAccounts;
    mapping(uint256 => Account.Info) accounts;

    constructor(address VPoolFactory_) BridgeFactoryAndHouse(VPoolFactory_) {}

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts++];
        newAccount.owner = msg.sender;
    }

    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {}

    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {}

    function swapTokenAmount(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vTokenAmount
    ) external {}

    function swapTokenNotional(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vBaseAmount
    ) external {}

    function updateRangeOrder(
        uint256 accountNo,
        address vTokenAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external {}

    function removeLimitOrder(
        uint256 accountNo,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper
    ) external {}

    function liquidateLiquidityPositions(uint256 accountNo) external {}

    function liquidateTokenPosition(uint256 accountNo, uint32 vTokenTruncatedAddress) external {}
}
