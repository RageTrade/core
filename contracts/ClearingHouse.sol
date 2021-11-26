//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account, LiquidityChangeParams, LiquidationParams } from './libraries/Account.sol';
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

    LiquidationParams public liquidationParams;
    uint256 public removeLimitOrderFee;
    uint256 public minNotionalValue;

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
        returns (address vTokenAddress)
    {
        vTokenAddress = vTokenAddresses[vTokenTruncatedAddress];
        if (vTokenAddress == address(0)) revert UninitializedToken(vTokenTruncatedAddress);
        if (isDepositCheck && !supportedDeposits[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
        if (!isDepositCheck && !supportedVTokens[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
    }

    function setLiquidationParameters(LiquidationParams calldata _liquidationParams)
        external
        onlyGovernanceOrTeamMultisig
    {
        liquidationParams = _liquidationParams;
    }

    function setRemoveLimitOrderFee(uint256 _removeLimitOrderFee) external onlyGovernanceOrTeamMultisig {
        removeLimitOrderFee = _removeLimitOrderFee;
    }

    function setMinNotionalValue(uint256 _minNotionalValue) external onlyGovernanceOrTeamMultisig {
        minNotionalValue = _minNotionalValue;
    }

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = numAccounts;

        emit Account.AccountCreated(msg.sender, numAccounts++);
    }

    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            totalProtocolFee += IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
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

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transferFrom(msg.sender, address(this), amount);

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

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        account.removeMargin(vTokenAddress, amount, vTokenAddresses, constants);
        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transfer(msg.sender, amount);

        emit Account.WithdrawMargin(accountNo, vTokenAddress, amount);
    }

    function removeProfit(uint256 accountNo, uint256 amount) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        account.removeProfit(amount, vTokenAddresses, constants);
        IERC20(realBase).transfer(msg.sender, amount);

        emit Account.WithdrawProfit(accountNo, amount);
    }

    function swapTokenAmount(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vTokenAmount
    ) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        (, int256 vBaseAmount) = account.swapTokenAmount(vTokenAddress, vTokenAmount, vTokenAddresses, constants);

        uint256 vBaseAmountAbs = uint256(vBaseAmount.abs());
        if (vBaseAmountAbs < minNotionalValue) revert LowNotionalValue(vBaseAmountAbs);
    }

    function swapTokenNotional(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int256 vBaseAmount
    ) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        account.swapTokenNotional(vTokenAddress, vBaseAmount, vTokenAddresses, constants);

        uint256 vBaseAmountAbs = uint256(vBaseAmount.abs());
        if (vBaseAmountAbs < minNotionalValue) revert LowNotionalValue(vBaseAmountAbs);
    }

    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        if (liquidityChangeParams.liquidityDelta > 0 && liquidityChangeParams.closeTokenPosition)
            revert InvalidLiquidityChangeParameters();

        int256 notionalValue = account.liquidityChange(
            vTokenAddress,
            liquidityChangeParams,
            vTokenAddresses,
            constants
        );

        uint256 notionalValueAbs = uint256(notionalValue.abs());
        if (notionalValueAbs != 0 && notionalValueAbs < minNotionalValue) revert LowNotionalValue(notionalValueAbs);
    }

    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external {
        Account.Info storage account = accounts[accountNo];

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        account.removeLimitOrder(vTokenAddress, tickLower, tickUpper, removeLimitOrderFee, constants);

        IERC20(realBase).transfer(msg.sender, removeLimitOrderFee);
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

        IERC20(realBase).transfer(msg.sender, uint256(keeperFee));
        transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    function liquidateTokenPosition(uint256 accountNo, uint32 vTokenTruncatedAddress) external {
        Account.Info storage account = accounts[accountNo];

        address vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        (int256 keeperFee, int256 insuranceFundFee) = account.liquidateTokenPosition(
            vTokenAddress,
            liquidationParams,
            vTokenAddresses,
            constants
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        IERC20(realBase).transfer(msg.sender, uint256(keeperFee));
        transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateTokenPosition(
            accountNo,
            vTokenAddress,
            msg.sender,
            accountFee,
            keeperFee,
            insuranceFundFee
        );
    }

    function transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            IERC20(realBase).transfer(insuranceFundAddress, uint256(insuranceFundFee));
        } else {
            IInsuranceFund(insuranceFundAddress).claim(uint256(-insuranceFundFee));
        }
    }
}
