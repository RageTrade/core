//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { CTokenDepositSet } from './CTokenDepositSet.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { VTokenLib } from './VTokenLib.sol';
import { CTokenLib } from './CTokenLib.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { VTokenPositionSet } from './VTokenPositionSet.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVBase } from '../interfaces/IVBase.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { console } from 'hardhat/console.sol';

library Account {
    using Account for Account.UserInfo;
    using CTokenDepositSet for CTokenDepositSet.Info;
    using FullMath for uint256;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;
    using VTokenLib for IVToken;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;

    /// @notice account info for user
    /// @param owner specifies the account owner
    /// @param tokenPositions is set of all open token positions
    /// @param tokenDeposits is set of all deposits
    struct UserInfo {
        address owner;
        VTokenPositionSet.Set tokenPositions;
        CTokenDepositSet.Info tokenDeposits;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    struct ProtocolInfo {
        // rage trade pools
        mapping(IVToken => IClearingHouse.RageTradePool) pools;
        // conversion from compressed addressed to full address
        mapping(uint32 => CTokenLib.CToken) rTokens;
        mapping(uint32 => IVToken) vTokens;
        // virtual base
        IVBase vBase;
        IERC20 rBase;
        // accounting settings
        LiquidationParams liquidationParams;
        uint256 minRequiredMargin;
        uint256 removeLimitOrderFee;
        uint256 minimumOrderNotional;
        // reserved for adding slots in future
        uint256[100] _emptySlots;
    }

    /// @notice parameters to be used for liquidation
    /// @param liquidationFeeFraction specifies the percentage of notional value liquidated to be charged as liquidation fees (scaled by 1e5)
    /// @param tokenLiquidationPriceDeltaBps specifies the price delta from current perp price at which the liquidator should get the position (scaled by 1e4)
    /// @param insuranceFundFeeShare specifies the fee share for insurance fund out of the total liquidation fee (scaled by 1e4)
    struct LiquidationParams {
        uint16 liquidationFeeFraction;
        uint16 tokenLiquidationPriceDeltaBps;
        uint16 insuranceFundFeeShareBps;
    }

    /// @notice error to denote that there is not enough margin for the transaction to go through
    /// @param accountMarketValue shows the account market value after the transaction is executed
    /// @param totalRequiredMargin shows the total required margin after the transaction is executed
    error InvalidTransactionNotEnoughMargin(int256 accountMarketValue, int256 totalRequiredMargin);

    /// @notice error to denote that there is not enough profit during profit withdrawal
    /// @param totalProfit shows the value of positions at the time of execution after removing amount specified
    error InvalidTransactionNotEnoughProfit(int256 totalProfit);

    /// @notice error to denote that there is enough margin, hence the liquidation is invalid
    /// @param accountMarketValue shows the account market value before liquidation
    /// @param totalRequiredMargin shows the total required margin before liquidation
    error InvalidLiquidationAccountAbovewater(int256 accountMarketValue, int256 totalRequiredMargin);

    /// @notice error to denote that there are active ranges present during token liquidation, hence the liquidation is invalid
    /// @param vToken shows the token address for which range is active
    error InvalidLiquidationActiveRangePresent(IVToken vToken);

    /// @notice denotes new account creation
    /// @param ownerAddress wallet address of account owner
    /// @param accountNo serial number of the account
    event AccountCreated(address indexed ownerAddress, uint256 accountNo);

    /// @notice denotes deposit of margin
    /// @param accountNo serial number of the account
    /// @param rTokenAddress token in which margin is deposited
    /// @param amount amount of tokens deposited
    event DepositMargin(uint256 indexed accountNo, address indexed rTokenAddress, uint256 amount);

    /// @notice denotes withdrawal of margin
    /// @param accountNo serial number of the account
    /// @param rTokenAddress token in which margin is withdrawn
    /// @param amount amount of tokens withdrawn
    event WithdrawMargin(uint256 indexed accountNo, address indexed rTokenAddress, uint256 amount);

    /// @notice denotes withdrawal of profit in base token
    /// @param accountNo serial number of the account
    /// @param amount amount of profit withdrawn
    event UpdateProfit(uint256 indexed accountNo, int256 amount);

    /// @notice denotes token position change
    /// @param accountNo serial number of the account
    /// @param vToken address of token whose position was taken
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event TokenPositionChange(
        uint256 indexed accountNo,
        IVToken indexed vToken,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes token position change due to liquidity add/remove
    /// @param accountNo serial number of the account
    /// @param vToken address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    event LiquidityTokenPositionChange(
        uint256 indexed accountNo,
        IVToken indexed vToken,
        int24 tickLower,
        int24 tickUpper,
        int256 tokenAmountOut
    );

    /// @notice denotes liquidity add/remove
    /// @param accountNo serial number of the account
    /// @param vToken address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param liquidityDelta change in liquidity value
    /// @param limitOrderType the type of range position
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event LiquidityChange(
        uint256 indexed accountNo,
        IVToken indexed vToken,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        IClearingHouse.LimitOrderType limitOrderType,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes funding payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountNo serial number of the account
    /// @param vToken address of token for which funding was paid
    /// @param tickLower lower tick of the range for which funding was paid
    /// @param tickUpper upper tick of the range for which funding was paid
    /// @param amount amount of funding paid (negative) or received (positive)
    event FundingPayment(
        uint256 indexed accountNo,
        IVToken indexed vToken,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /// @notice denotes fee payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountNo serial number of the account
    /// @param vToken address of token for which fee was paid
    /// @param tickLower lower tick of the range for which fee was paid
    /// @param tickUpper upper tick of the range for which fee was paid
    /// @param amount amount of fee paid (negative) or received (positive)
    event LiquidityFee(
        uint256 indexed accountNo,
        IVToken indexed vToken,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /// @notice denotes protocol fee withdrawal from a pool wrapper
    /// @param wrapperAddress address of token for which fee was paid
    /// @param feeAmount amount of protocol fee which was withdrawn
    event ProtocolFeeWithdrawm(address indexed wrapperAddress, uint256 feeAmount);

    /// @notice denotes range position liquidation event
    /// @dev all range positions are liquidated and the current tokens inside the range are added in as token positions to the account
    /// @param accountNo serial number of the account
    /// @param keeperAddress address of keeper who performed the liquidation
    /// @param liquidationFee total liquidation fee charged to the account
    /// @param keeperFee total liquidaiton fee paid to the keeper (positive only)
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enought to cover the fee)
    event LiquidateRanges(
        uint256 indexed accountNo,
        address indexed keeperAddress,
        int256 liquidationFee,
        int256 keeperFee,
        int256 insuranceFundFee
    );

    /// @notice denotes token position liquidation event
    /// @dev the selected token position is take from the current account and moved to liquidatorAccount at a discounted prive to current pool price
    /// @param accountNo serial number of the account
    /// @param liquidatorAccountNo  account which performed the liquidation
    /// @param vToken address of token for whose position was liquidated
    /// @param liquidationBps the fraction of current position which was liquidated in bps
    /// @param liquidationPriceX128 price at which liquidation was performed
    /// @param liquidatorPriceX128 discounted price at which tokens were transferred to the liquidator account
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enough to cover the fee)
    event LiquidateTokenPosition(
        uint256 indexed accountNo,
        uint256 indexed liquidatorAccountNo,
        IVToken indexed vToken,
        uint16 liquidationBps,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 insuranceFundFee
    );

    /// @notice checks if 'account' is initialized
    /// @param account pointer to 'account' struct
    function _isInitialized(UserInfo storage account) internal view returns (bool) {
        return account.owner != address(0);
    }

    /// @notice updates the base balance for 'account' by 'amount'
    /// @param account pointer to 'account' struct
    /// @param amount amount of balance to update
    /// @param protocol platform constants
    function _updateBaseBalance(
        UserInfo storage account,
        int256 amount,
        Account.ProtocolInfo storage protocol
    ) internal returns (IClearingHouse.BalanceAdjustments memory balanceAdjustments) {
        balanceAdjustments = IClearingHouse.BalanceAdjustments(amount, 0, 0);
        account.tokenPositions.update(balanceAdjustments, IVToken(address(protocol.vBase)), protocol);
    }

    /// @notice increases deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param realTokenAddress address of token to deposit
    /// @param amount amount of token to deposit
    function addMargin(
        UserInfo storage account,
        address realTokenAddress,
        uint256 amount
    ) external {
        // vBASE should be an immutable constant
        account.tokenDeposits.increaseBalance(realTokenAddress, amount);
    }

    /// @notice reduces deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param realTokenAddress address of token to remove
    /// @param amount amount of token to remove
    /// @param protocol set of all constants and token addresses
    function removeMargin(
        UserInfo storage account,
        address realTokenAddress,
        uint256 amount,
        Account.ProtocolInfo storage protocol,
        bool checkMargin
    ) external {
        account.tokenDeposits.decreaseBalance(realTokenAddress, amount);

        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice updates 'amount' of profit generated in base token
    /// @param account account to remove profit from
    /// @param amount amount of profit(base token) to add/remove
    /// @param protocol set of all constants and token addresses
    function updateProfit(
        UserInfo storage account,
        int256 amount,
        Account.ProtocolInfo storage protocol,
        bool checkMargin
    ) external {
        account._updateBaseBalance(amount, protocol);

        // TODO is not doing checkIfProfitAvailable in multicall safe?
        if (checkMargin && amount < 0) {
            account._checkIfProfitAvailable(protocol);
            account._checkIfMarginAvailable(true, protocol);
        }
    }

    /// @notice returns market value and required margin for the account based on current market conditions
    /// @dev (In case requiredMargin < minRequiredMargin then requiredMargin = minRequiredMargin)
    /// @param account account to check
    /// @param isInitialMargin true to use initial margin factor and false to use maintainance margin factor for calcualtion of required margin
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    /// @return totalRequiredMargin total margin required to keep the account above selected margin requirement (intial/maintainance)
    function getAccountValueAndRequiredMargin(
        UserInfo storage account,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) external view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        return account._getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    function _getAccountValueAndRequiredMargin(
        UserInfo storage account,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        accountMarketValue = account._getAccountValue(protocol);

        totalRequiredMargin = account.tokenPositions.getRequiredMargin(isInitialMargin, protocol.vTokens, protocol);
        if (!account.tokenPositions.isEmpty()) {
            totalRequiredMargin = totalRequiredMargin < int256(protocol.minRequiredMargin)
                ? int256(protocol.minRequiredMargin)
                : totalRequiredMargin;
        }
        return (accountMarketValue, totalRequiredMargin);
    }

    /// @notice returns market value for the account positions based on current market conditions
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    /// @return accountPositionProfits total market value of all the positions (token ) and deposits
    function getAccountPositionProfits(UserInfo storage account, Account.ProtocolInfo storage protocol)
        external
        view
        returns (int256 accountPositionProfits)
    {
        return account._getAccountPositionProfits(protocol);
    }

    function _getAccountPositionProfits(UserInfo storage account, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256 accountPositionProfits)
    {
        accountPositionProfits = account.tokenPositions.getAccountMarketValue(protocol.vTokens, protocol);
    }

    /// @notice returns market value for the account based on current market conditions
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    function _getAccountValue(UserInfo storage account, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256 accountMarketValue)
    {
        accountMarketValue = account._getAccountPositionProfits(protocol);
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(protocol);
        return (accountMarketValue);
    }

    /// @notice checks if market value > required margin else revert with InvalidTransactionNotEnoughMargin
    /// @param account account to check
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param protocol set of all constants and token addresses
    function checkIfMarginAvailable(
        UserInfo storage account,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) external view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    function _checkIfMarginAvailable(
        UserInfo storage account,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) internal view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if profit is available to withdraw base token (token value of all positions > 0) else revert with InvalidTransactionNotEnoughProfit
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    function checkIfProfitAvailable(UserInfo storage account, Account.ProtocolInfo storage protocol) external view {
        _checkIfProfitAvailable(account, protocol);
    }

    function _checkIfProfitAvailable(UserInfo storage account, Account.ProtocolInfo storage protocol) internal view {
        int256 totalPositionValue = account._getAccountPositionProfits(protocol);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice swaps 'vToken' of token amount equal to 'swapParams.amount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @notice isNotional specifies whether the amount represents token amount (false) or base amount(true)
    /// @notice isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
    /// @notice sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
    /// @param account account to swap tokens for
    /// @param vToken address of the token to swap
    /// @param swapParams parameters for the swap (Includes - amount, sqrtPriceLimit, isNotional, isPartialAllowed)
    /// @param protocol set of all constants and token addresses
    function swapToken(
        UserInfo storage account,
        IVToken vToken,
        IClearingHouse.SwapParams memory swapParams,
        Account.ProtocolInfo storage protocol,
        bool checkMargin
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback and send to the pool
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.swapToken(vToken, swapParams, protocol);

        // after all the stuff, account should be above water
        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice changes range liquidity 'vToken' of market value equal to 'vTokenNotional'
    /// @notice if 'liquidityDelta'>0 then liquidity is added and if 'liquidityChange'<0 then liquidity is removed
    /// @notice the liquidity change is reverted if the sqrt price at the time of execution is beyond 'slippageToleranceBps' of 'sqrtPriceCurrent' supplied
    /// @notice whenever liquidity change is done the external token position is taken out. If 'closeTokenPosition' is true this is swapped out else it is added to the current token position
    /// @param account account to change liquidity
    /// @param vToken address of token to swap
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta, sqrtPriceCurrent, slippageToleranceBps, closeTokenPosition, limit order type
    /// @param protocol set of all constants and token addresses
    function liquidityChange(
        UserInfo storage account,
        IVToken vToken,
        IClearingHouse.LiquidityChangeParams memory liquidityChangeParams,
        Account.ProtocolInfo storage protocol,
        bool checkMargin
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // mint/burn tokens + fee + funding payment
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.liquidityChange(
            vToken,
            liquidityChangeParams,
            protocol
        );

        // after all the stuff, account should be above water
        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice computes keeper fee and insurance fund fee in case of liquidity position liquidation
    /// @dev keeperFee = liquidationFee*(1-insuranceFundFeeShare)+fixFee
    /// @dev insuranceFundFee = accountMarketValue - keeperFee (if accountMarketValue is not enough to cover the fees) else insurancFundFee = liquidationFee - keeperFee + fixFee
    /// @param accountMarketValue market value of account
    /// @param liquidationFee total liquidation fee to be charged to the account in case of an on time liquidation
    /// @param liquidationParams parameters including fixFee, insuranceFundFeeShareBps
    /// @return keeperFee map of vTokens allowed on the platform
    /// @return insuranceFundFee poolwrapper for token
    function _computeLiquidationFees(
        int256 accountMarketValue,
        int256 liquidationFee,
        uint256 fixFee,
        LiquidationParams memory liquidationParams
    ) internal pure returns (int256 keeperFee, int256 insuranceFundFee) {
        int256 fixFeeInt = int256(fixFee);
        keeperFee = liquidationFee.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4) + fixFeeInt;
        if (accountMarketValue - fixFeeInt - liquidationFee < 0) {
            insuranceFundFee = accountMarketValue - keeperFee;
        } else {
            insuranceFundFee = liquidationFee - keeperFee + fixFeeInt;
        }
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @notice charges a liquidation fee to the account and pays partially to the insurance fund and rest to the keeper.
    /// @dev insurance fund covers the remaining fee if the account market value is not enough
    /// @param account account to liquidate
    /// @param protocol set of all constants and token addresses
    function liquidateLiquidityPositions(
        UserInfo storage account,
        uint256 fixFee,
        Account.ProtocolInfo storage protocol
    ) external returns (int256 keeperFee, int256 insuranceFundFee) {
        // check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 notionalAmountClosed;

        (accountMarketValue, totalRequiredMargin) = account._getAccountValueAndRequiredMargin(false, protocol);
        if (accountMarketValue > totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(protocol.vTokens, protocol);

        int256 liquidationFee = notionalAmountClosed.mulDiv(protocol.liquidationParams.liquidationFeeFraction, 1e5);
        (keeperFee, insuranceFundFee) = _computeLiquidationFees(
            accountMarketValue,
            liquidationFee,
            fixFee,
            protocol.liquidationParams
        );

        account._updateBaseBalance(-(keeperFee + insuranceFundFee), protocol);
    }

    /// @notice computes the liquidation & liquidator price and insurance fund fee for token liquidation
    /// @param tokensToTrade amount of tokens to trade for liquidation
    /// @param vToken vToken being liquidated
    /// @param protocol set of all constants and token addresses
    function _getLiquidationPriceX128AndFee(
        int256 tokensToTrade,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    )
        internal
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        uint16 maintainanceMarginFactor = vToken.getMarginRatio(false, protocol);
        uint256 priceX128 = vToken.getVirtualCurrentPriceX128(protocol);
        uint256 priceDeltaX128 = priceX128.mulDiv(protocol.liquidationParams.tokenLiquidationPriceDeltaBps, 1e4).mulDiv(
            maintainanceMarginFactor,
            1e5
        );
        if (tokensToTrade < 0) {
            liquidationPriceX128 = priceX128 - priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 -
                priceDeltaX128.mulDiv(1e4 - protocol.liquidationParams.insuranceFundFeeShareBps, 1e4);
            insuranceFundFee = -tokensToTrade.mulDiv(liquidatorPriceX128 - liquidationPriceX128, FixedPoint128.Q128);
        } else {
            liquidationPriceX128 = priceX128 + priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 +
                priceDeltaX128.mulDiv(1e4 - protocol.liquidationParams.insuranceFundFeeShareBps, 1e4);
            insuranceFundFee = tokensToTrade.mulDiv(liquidationPriceX128 - liquidatorPriceX128, FixedPoint128.Q128);
        }
    }

    /// @notice exchanges token position between account (at liquidationPrice) and liquidator account (at liquidator price)
    /// @notice also charges fixFee from the account and pays to liquidator
    /// @param account is account being liquidated
    /// @param liquidatorAccount is account of liquidator
    /// @param vToken map of vTokens allowed on the platform
    /// @param tokensToTrade number of tokens to trade
    /// @param liquidationPriceX128 price at which tokens should be traded out
    /// @param liquidatorPriceX128 discounted price at which tokens should be given to liquidator
    /// @param fixFee is the fee to be given to liquidator to compensate for gas price
    /// @param protocol platform constants
    function _updateLiquidationAccounts(
        UserInfo storage account,
        UserInfo storage liquidatorAccount,
        IVToken vToken,
        int256 tokensToTrade,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 fixFee,
        Account.ProtocolInfo storage protocol
    ) internal returns (IClearingHouse.BalanceAdjustments memory liquidatorBalanceAdjustments) {
        vToken.vPoolWrapper(protocol).updateGlobalFundingState();

        IClearingHouse.BalanceAdjustments memory balanceAdjustments = IClearingHouse.BalanceAdjustments({
            vBaseIncrease: -tokensToTrade.mulDiv(liquidationPriceX128, FixedPoint128.Q128) - fixFee,
            vTokenIncrease: tokensToTrade,
            traderPositionIncrease: tokensToTrade
        });

        account.tokenPositions.update(balanceAdjustments, vToken, protocol);
        emit Account.TokenPositionChange(
            account.tokenPositions.accountNo,
            vToken,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vBaseIncrease
        );

        liquidatorBalanceAdjustments = IClearingHouse.BalanceAdjustments({
            vBaseIncrease: tokensToTrade.mulDiv(liquidatorPriceX128, FixedPoint128.Q128) + fixFee,
            vTokenIncrease: -tokensToTrade,
            traderPositionIncrease: -tokensToTrade
        });

        liquidatorAccount.tokenPositions.update(liquidatorBalanceAdjustments, vToken, protocol);
        emit Account.TokenPositionChange(
            liquidatorAccount.tokenPositions.accountNo,
            vToken,
            liquidatorBalanceAdjustments.vTokenIncrease,
            liquidatorBalanceAdjustments.vBaseIncrease
        );
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param vToken address of token to swap
    /// @param protocol set of all constants and token addresses
    function liquidateTokenPosition(
        UserInfo storage account,
        UserInfo storage liquidatorAccount,
        uint16 liquidationBps,
        IVToken vToken,
        uint256 fixFee,
        Account.ProtocolInfo storage protocol,
        bool checkMargin
    )
        external
        returns (int256 insuranceFundFee, IClearingHouse.BalanceAdjustments memory liquidatorBalanceAdjustments)
    {
        if (account.tokenPositions.getIsTokenRangeActive(vToken, protocol))
            revert InvalidLiquidationActiveRangePresent(vToken);

        {
            (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
                false,
                protocol
            );

            if (accountMarketValue > totalRequiredMargin) {
                revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
            }
        }

        int256 tokensToTrade;
        {
            VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
                vToken,
                false,
                protocol
            );
            tokensToTrade = -vTokenPosition.balance.mulDiv(liquidationBps, 1e4);
        }

        uint256 liquidationPriceX128;
        uint256 liquidatorPriceX128;
        {
            (liquidationPriceX128, liquidatorPriceX128, insuranceFundFee) = _getLiquidationPriceX128AndFee(
                tokensToTrade,
                vToken,
                protocol
            );

            liquidatorBalanceAdjustments = _updateLiquidationAccounts(
                account,
                liquidatorAccount,
                vToken,
                tokensToTrade,
                liquidationPriceX128,
                liquidatorPriceX128,
                int256(fixFee),
                protocol
            );
        }
        {
            int256 accountMarketValueFinal = account._getAccountValue(protocol);

            if (accountMarketValueFinal < 0) {
                insuranceFundFee = accountMarketValueFinal;
                account._updateBaseBalance(-accountMarketValueFinal, protocol);
            }
        }

        if (checkMargin) liquidatorAccount._checkIfMarginAvailable(false, protocol);

        emit Account.LiquidateTokenPosition(
            account.tokenPositions.accountNo,
            liquidatorAccount.tokenPositions.accountNo,
            vToken,
            liquidationBps,
            liquidationPriceX128,
            liquidatorPriceX128,
            insuranceFundFee
        );
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param vToken address of token for the range
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        UserInfo storage account,
        IVToken vToken,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFeeAndFixFee,
        Account.ProtocolInfo storage protocol
    ) external {
        account.tokenPositions.removeLimitOrder(vToken, tickLower, tickUpper, protocol);

        account._updateBaseBalance(-int256(limitOrderFeeAndFixFee), protocol);
    }

    function getView(UserInfo storage account, Account.ProtocolInfo storage protocol)
        external
        view
        returns (
            address owner,
            int256 vBaseBalance,
            IClearingHouse.DepositTokenView[] memory tokenDeposits,
            IClearingHouse.VTokenPositionView[] memory tokenPositions
        )
    {
        owner = account.owner;
        tokenDeposits = account.tokenDeposits.getView(protocol);
        (vBaseBalance, tokenPositions) = account.tokenPositions.getView(protocol);
    }
}
