//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account, LiquidityChangeParams, LiquidationParams, SwapParams } from './libraries/Account.sol';
import { LimitOrderType } from './libraries/LiquidityPosition.sol';
import { ClearingHouseState } from './ClearingHouseState.sol';
import { IClearingHouse } from './interfaces/IClearingHouse.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';
import { IInsuranceFund } from './interfaces/IInsuranceFund.sol';
import { IVPoolWrapper } from './interfaces/IVPoolWrapper.sol';
import { SignedMath } from './libraries/SignedMath.sol';

contract ClearingHouse is ClearingHouseState, IClearingHouse {
    using Account for Account.Info;
    using VTokenLib for VTokenAddress;
    using SignedMath for int256;

    address public immutable realBase;
    address public immutable insuranceFundAddress;

    uint256 public numAccounts;
    mapping(uint256 => Account.Info) accounts;

    constructor(
        address VPoolFactory,
        address _realBase,
        address _insuranceFundAddress
    ) ClearingHouseState(VPoolFactory) {
        realBase = _realBase;
        insuranceFundAddress = _insuranceFundAddress;
    }

    function getTokenAddressWithChecks(uint32 vTokenTruncatedAddress, bool isDepositCheck)
        internal
        view
        returns (VTokenAddress vTokenAddress)
    {
        vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        if (vTokenAddress.eq(address(0))) revert UninitializedToken(vTokenTruncatedAddress);
        if (isDepositCheck && !supportedDeposits[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
        if (!isDepositCheck && !supportedVTokens[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
    }

    function createAccount() external returns (uint256 newAccountId) {
        newAccountId = numAccounts;
        numAccounts = newAccountId + 1; // SSTORE

        Account.Info storage newAccount = accounts[newAccountId];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = newAccountId;

        emit Account.AccountCreated(msg.sender, newAccountId);
    }

    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            uint256 wrapperFee = IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
            emit Account.ProtocolFeeWithdrawm(wrapperAddresses[i], wrapperFee);
            totalProtocolFee += wrapperFee;
        }
        IERC20(realBase).transfer(teamMultisig(), totalProtocolFee);
    }

    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            IERC20(vTokenAddress.realToken()).transferFrom(msg.sender, address(this), amount);
        } else {
            IERC20(realBase).transferFrom(msg.sender, address(this), amount);
        }

        account.addMargin(vTokenAddress, amount, constants);

        emit Account.DepositMargin(accountNo, vTokenAddress, amount);
    }

    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        account.removeMargin(vTokenAddress, amount, vTokenAddresses, liquidationParams.minRequiredMargin, constants);

        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            IERC20(vTokenAddress.realToken()).transfer(msg.sender, amount);
        } else {
            IERC20(realBase).transfer(msg.sender, amount);
        }

        emit Account.WithdrawMargin(accountNo, vTokenAddress, amount);
    }

    function removeProfit(uint256 accountNo, uint256 amount) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        account.removeProfit(amount, vTokenAddresses, liquidationParams.minRequiredMargin, constants);
        IERC20(realBase).transfer(msg.sender, amount);

        emit Account.WithdrawProfit(accountNo, amount);
    }

    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        return
            account.swapToken(
                vTokenAddress,
                swapParams,
                vTokenAddresses,
                liquidationParams.minRequiredMargin,
                constants
            );
    }

    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        if (liquidityChangeParams.liquidityDelta > 0 && liquidityChangeParams.closeTokenPosition)
            revert InvalidLiquidityChangeParameters();

        return
            account.liquidityChange(
                vTokenAddress,
                liquidityChangeParams,
                vTokenAddresses,
                liquidationParams.minRequiredMargin,
                constants
            );
    }

    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 keeperFee) {
        Account.Info storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        account.removeLimitOrder(
            vTokenAddress,
            tickLower,
            tickUpper,
            removeLimitOrderFee + liquidationParams.fixFee,
            constants
        );
        keeperFee = removeLimitOrderFee + liquidationParams.fixFee;

        IERC20(realBase).transfer(msg.sender, keeperFee);
        // emit Account.LiqudityChange(accountNo, tickLower, tickUpper, liquidityDelta, 0, 0, 0);
    }

    function liquidateLiquidityPositions(uint256 accountNo) external returns (int256 keeperFee) {
        Account.Info storage account = accounts[accountNo];
        int256 insuranceFundFee;
        (keeperFee, insuranceFundFee) = account.liquidateLiquidityPositions(
            vTokenAddresses,
            liquidationParams,
            constants
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        IERC20(realBase).transfer(msg.sender, uint256(keeperFee));
        transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external {
        if (liquidationBps > 10000) revert InvalidTokenLiquidationParameters();
        Account.Info storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        int256 insuranceFundFee = account.liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            liquidationBps,
            vTokenAddress,
            liquidationParams,
            vTokenAddresses,
            constants
        );

        transferInsuranceFundFee(insuranceFundFee);
    }

    function transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            IERC20(realBase).transfer(insuranceFundAddress, uint256(insuranceFundFee));
        } else {
            IInsuranceFund(insuranceFundAddress).claim(uint256(-insuranceFundFee));
        }
    }
}
