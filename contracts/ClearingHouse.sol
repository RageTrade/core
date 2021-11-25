//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account, LiquidityChangeParams, LiquidationParams } from './libraries/Account.sol';
import { LimitOrderType } from './libraries/LiquidityPosition.sol';
import { ClearingHouseState } from './ClearingHouseState.sol';
import { IClearingHouse } from './interfaces/IClearingHouse.sol';

contract ClearingHouse is ClearingHouseState, IClearingHouse {
    LiquidationParams public liquidationParams;
    using Account for Account.Info;
    uint256 public numAccounts;
    mapping(uint256 => Account.Info) accounts;
    address public immutable realBase;

    constructor(address VPoolFactory, address _realBase) ClearingHouseState(VPoolFactory) {
        realBase = _realBase;
    }

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;

        emit Account.AccountCreated(msg.sender, numAccounts++);
    }

    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {
        Account.Info storage account = accounts[accountNo];
        require(msg.sender == account.owner, 'Access Denied');

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedDeposits[vTokenAddress], 'Unsupported Token');

        account.addMargin(vTokenAddress, amount, constants);

        emit Account.DepositMargin(accountNo, vTokenAddress, amount);
    }

    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {
        Account.Info storage account = accounts[accountNo];
        require(msg.sender == account.owner, 'Access Denied');

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedDeposits[vTokenAddress], 'Unsupported Token');

        account.removeMargin(vTokenAddress, amount, vTokenAddresses, constants);

        emit Account.WithdrawMargin(accountNo, vTokenAddress, amount);
    }

    function swapTokenAmount(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vTokenAmount
    ) external {
        Account.Info storage account = accounts[accountNo];
        require(msg.sender == account.owner, 'Access Denied');

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedVTokens[vTokenAddress], 'Unsupported Token');

        (int256 vTokenAmountOut, int256 vBaseAmountOut) = account.swapTokenAmount(
            vTokenAddress,
            vTokenAmount,
            vTokenAddresses,
            constants
        );
    }

    function swapTokenNotional(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vBaseAmount
    ) external {
        Account.Info storage account = accounts[accountNo];
        require(msg.sender == account.owner, 'Access Denied');

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedVTokens[vTokenAddress], 'Unsupported Token');

        (int256 vTokenAmountOut, int256 vBaseAmountOut) = account.swapTokenNotional(
            vTokenAddress,
            vBaseAmount,
            vTokenAddresses,
            constants
        );
    }

    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external {
        Account.Info storage account = accounts[accountNo];
        require(msg.sender == account.owner, 'Access Denied');

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedVTokens[vTokenAddress], 'Unsupported Token');

        account.liquidityChange(vTokenAddress, liquidityChangeParams, vTokenAddresses, constants);
    }

    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external {
        Account.Info storage account = accounts[accountNo];

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedVTokens[vTokenAddress], 'Unsupported Token');

        //TODO: Add remove limit order fee immutable and replace 0 with that
        account.removeLimitOrder(vTokenAddress, tickLower, tickUpper, 0, constants);

        // emit Account.LiqudityChange(accountNo, tickLower, tickUpper, liquidityDelta, 0, 0, 0);
    }

    function liquidateLiquidityPositions(uint256 accountNo) external {
        Account.Info storage account = accounts[accountNo];

        (int256 keeperFee, int256 insuranceFundFee) = account.liquidateLiquidityPositions(
            liquidationParams.liquidationFeeFraction,
            vTokenAddresses,
            constants
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    function liquidateTokenPosition(uint256 accountNo, uint32 vTokenTruncatedAddress) external {
        Account.Info storage account = accounts[accountNo];

        address vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        require(supportedVTokens[vTokenAddress], 'Unsupported Token');

        (int256 keeperFee, int256 insuranceFundFee) = account.liquidateTokenPosition(
            vTokenAddress,
            liquidationParams,
            vTokenAddresses,
            constants
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        emit Account.LiquidateTokenPosition(
            accountNo,
            vTokenAddress,
            msg.sender,
            accountFee,
            keeperFee,
            insuranceFundFee
        );
    }
}
