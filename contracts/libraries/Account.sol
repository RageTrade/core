//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { AddressHelper } from './AddressHelper.sol';
import { CollateralDeposit } from './CollateralDeposit.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { Protocol } from './Protocol.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { VTokenPositionSet } from './VTokenPositionSet.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IVToken } from '../interfaces/IVToken.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { console } from 'hardhat/console.sol';

library Account {
    using AddressHelper for address;
    using FullMath for uint256;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;

    using Account for Account.Info;
    using CollateralDeposit for CollateralDeposit.Set;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;
    using VTokenPosition for VTokenPosition.Info;
    using VTokenPositionSet for VTokenPosition.Set;

    /// @notice account info for user
    /// @param owner specifies the account owner
    /// @param tokenPositions is set of all open token positions
    /// @param tokenDeposits is set of all deposits
    struct Info {
        uint96 id;
        address owner;
        VTokenPosition.Set tokenPositions;
        CollateralDeposit.Set tokenDeposits;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
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
    /// @param poolId shows the poolId for which range is active
    error InvalidLiquidationActiveRangePresent(uint32 poolId);

    /// @notice denotes withdrawal of profit in base token
    /// @param accountId serial number of the account
    /// @param amount amount of profit withdrawn
    event ProfitUpdated(uint256 indexed accountId, int256 amount);

    /// @notice denotes token position change
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vtoken whose position was taken
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event TokenPositionChanged(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes token position change due to liquidity add/remove
    /// @param accountId serial number of the account
    /// @param poolId address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    event TokenPositionChangedDueToLiquidityChanged(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 tokenAmountOut
    );

    /// @notice denotes liquidity add/remove
    /// @param accountId serial number of the account
    /// @param poolId address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param liquidityDelta change in liquidity value
    /// @param limitOrderType the type of range position
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event LiquidityChanged(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        IClearingHouseEnums.LimitOrderType limitOrderType,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes funding payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountId serial number of the account
    /// @param poolId address of token for which funding was paid
    /// @param tickLower lower tick of the range for which funding was paid
    /// @param tickUpper upper tick of the range for which funding was paid
    /// @param amount amount of funding paid (negative) or received (positive)
    event FundingPaymentRealized(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /// @notice denotes fee payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountId serial number of the account
    /// @param poolId address of token for which fee was paid
    /// @param tickLower lower tick of the range for which fee was paid
    /// @param tickUpper upper tick of the range for which fee was paid
    /// @param amount amount of fee paid (negative) or received (positive)
    event LiquidityPositionEarningsRealized(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /// @notice denotes protocol fee withdrawal from a pool wrapper
    /// @param wrapperAddress address of token for which fee was paid
    /// @param feeAmount amount of protocol fee which was withdrawn
    event ProtocolFeesWithdrawn(address indexed wrapperAddress, uint256 feeAmount);

    /// @notice denotes range position liquidation event
    /// @dev all range positions are liquidated and the current tokens inside the range are added in as token positions to the account
    /// @param accountId serial number of the account
    /// @param keeperAddress address of keeper who performed the liquidation
    /// @param liquidationFee total liquidation fee charged to the account
    /// @param keeperFee total liquidaiton fee paid to the keeper (positive only)
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enought to cover the fee)
    event LiquidityPositionsLiquidated(
        uint256 indexed accountId,
        address indexed keeperAddress,
        int256 liquidationFee,
        int256 keeperFee,
        int256 insuranceFundFee
    );

    /// @notice denotes token position liquidation event
    /// @dev the selected token position is take from the current account and moved to liquidatorAccount at a discounted prive to current pool price
    /// @param accountId serial number of the account
    /// @param liquidatorAccountId  account which performed the liquidation
    /// @param poolId id of the rage trade pool for whose position was liquidated
    /// @param liquidationBps the fraction of current position which was liquidated in bps
    /// @param liquidationPriceX128 price at which liquidation was performed
    /// @param liquidatorPriceX128 discounted price at which tokens were transferred to the liquidator account
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enough to cover the fee)
    event TokenPositionLiquidated(
        uint256 indexed accountId,
        uint256 indexed liquidatorAccountId,
        uint32 indexed poolId,
        uint16 liquidationBps,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        uint256 fixFee,
        int256 insuranceFundFee
    );

    /// @notice checks if 'account' is initialized
    /// @param account pointer to 'account' struct
    function _isInitialized(Account.Info storage account) internal view returns (bool) {
        return account.owner != address(0);
    }

    /// @notice updates the base balance for 'account' by 'amount'
    /// @param account pointer to 'account' struct
    /// @param amount amount of balance to update
    /// @param protocol platform constants
    function _updateBaseBalance(
        Account.Info storage account,
        int256 amount,
        Protocol.Info storage protocol
    ) internal returns (IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments) {
        balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(amount, 0, 0);
        account.tokenPositions.update(account.id, balanceAdjustments, address(protocol.vQuote).truncate(), protocol);
    }

    /// @notice increases deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param collateralId collateral id of the token
    /// @param amount amount of token to deposit
    function addMargin(
        Account.Info storage account,
        uint32 collateralId,
        uint256 amount
    ) external {
        // vBASE should be an immutable constant
        account.tokenDeposits.increaseBalance(collateralId, amount);
    }

    /// @notice reduces deposit balance of 'vToken' by 'amount'
    /// @param account account to deposit balance into
    /// @param collateralId collateral id of the token
    /// @param amount amount of token to remove
    /// @param protocol set of all constants and token addresses
    function removeMargin(
        Account.Info storage account,
        uint32 collateralId,
        uint256 amount,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external {
        account.tokenDeposits.decreaseBalance(collateralId, amount);

        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice updates 'amount' of profit generated in base token
    /// @param account account to remove profit from
    /// @param amount amount of profit(base token) to add/remove
    /// @param protocol set of all constants and token addresses
    function updateProfit(
        Account.Info storage account,
        int256 amount,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external {
        account._updateBaseBalance(amount, protocol);

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
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) external view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        return account._getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }

    function _getAccountValueAndRequiredMargin(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        accountMarketValue = account._getAccountValue(protocol);

        totalRequiredMargin = account.tokenPositions.getRequiredMargin(isInitialMargin, protocol);
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
    function getAccountPositionProfits(Account.Info storage account, Protocol.Info storage protocol)
        external
        view
        returns (int256 accountPositionProfits)
    {
        return account._getAccountPositionProfits(protocol);
    }

    function _getAccountPositionProfits(Account.Info storage account, Protocol.Info storage protocol)
        internal
        view
        returns (int256 accountPositionProfits)
    {
        accountPositionProfits = account.tokenPositions.getAccountMarketValue(protocol);
    }

    /// @notice returns market value for the account based on current market conditions
    /// @param account account to check
    /// @param protocol set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    function _getAccountValue(Account.Info storage account, Protocol.Info storage protocol)
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
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
    ) external view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account._getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    function _checkIfMarginAvailable(
        Account.Info storage account,
        bool isInitialMargin,
        Protocol.Info storage protocol
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
    function checkIfProfitAvailable(Account.Info storage account, Protocol.Info storage protocol) external view {
        _checkIfProfitAvailable(account, protocol);
    }

    function _checkIfProfitAvailable(Account.Info storage account, Protocol.Info storage protocol) internal view {
        int256 totalPositionValue = account._getAccountPositionProfits(protocol);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice swaps 'vToken' of token amount equal to 'swapParams.amount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @notice isNotional specifies whether the amount represents token amount (false) or base amount(true)
    /// @notice isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
    /// @notice sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
    /// @param account account to swap tokens for
    /// @param poolId id of the pool to swap tokens for
    /// @param swapParams parameters for the swap (Includes - amount, sqrtPriceLimit, isNotional, isPartialAllowed)
    /// @param protocol set of all constants and token addresses
    function swapToken(
        Account.Info storage account,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        // make a swap. vQuoteIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback and send to the pool
        (vTokenAmountOut, vQuoteAmountOut) = account.tokenPositions.swapToken(account.id, poolId, swapParams, protocol);

        // after all the stuff, account should be above water
        if (checkMargin) account._checkIfMarginAvailable(true, protocol);
    }

    /// @notice changes range liquidity 'vToken' of market value equal to 'vTokenNotional'
    /// @notice if 'liquidityDelta'>0 then liquidity is added and if 'liquidityChange'<0 then liquidity is removed
    /// @notice the liquidity change is reverted if the sqrt price at the time of execution is beyond 'slippageToleranceBps' of 'sqrtPriceCurrent' supplied
    /// @notice whenever liquidity change is done the external token position is taken out. If 'closeTokenPosition' is true this is swapped out else it is added to the current token position
    /// @param account account to change liquidity
    /// @param poolId id of the rage trade pool
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta, sqrtPriceCurrent, slippageToleranceBps, closeTokenPosition, limit order type
    /// @param protocol set of all constants and token addresses
    function liquidityChange(
        Account.Info storage account,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        Protocol.Info storage protocol,
        bool checkMargin
    ) external returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        // mint/burn tokens + fee + funding payment
        (vTokenAmountOut, vQuoteAmountOut) = account.tokenPositions.liquidityChange(
            account.id,
            poolId,
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
    /// @param notionalAmountClosed notional value of position closed
    /// @param fixFee additional fixfee to be paid to the keeper
    /// @param liquidationParams parameters including fixFee, insuranceFundFeeShareBps
    /// @return keeperFee map of vTokens allowed on the platform
    /// @return insuranceFundFee poolwrapper for token
    function _computeLiquidationFees(
        int256 accountMarketValue,
        uint256 notionalAmountClosed,
        uint256 fixFee,
        IClearingHouseStructures.LiquidationParams memory liquidationParams
    ) internal pure returns (int256 keeperFee, int256 insuranceFundFee) {
        uint256 liquidationFee = notionalAmountClosed.mulDiv(liquidationParams.liquidationFeeFraction, 1e5);

        liquidationFee = liquidationParams.maxRangeLiquidationFees < liquidationFee
            ? liquidationParams.maxRangeLiquidationFees
            : liquidationFee;
        int256 liquidationFeeInt = liquidationFee.toInt256();

        int256 fixFeeInt = int256(fixFee);
        keeperFee = liquidationFeeInt.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4) + fixFeeInt;
        if (accountMarketValue - fixFeeInt - liquidationFeeInt < 0) {
            insuranceFundFee = accountMarketValue - keeperFee;
        } else {
            insuranceFundFee = liquidationFeeInt - keeperFee + fixFeeInt;
        }
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @notice charges a liquidation fee to the account and pays partially to the insurance fund and rest to the keeper.
    /// @dev insurance fund covers the remaining fee if the account market value is not enough
    /// @param account account to liquidate
    /// @param protocol set of all constants and token addresses
    function liquidateLiquidityPositions(
        Account.Info storage account,
        uint256 fixFee,
        Protocol.Info storage protocol
    ) external returns (int256 keeperFee, int256 insuranceFundFee) {
        // check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        uint256 notionalAmountClosed;

        (accountMarketValue, totalRequiredMargin) = account._getAccountValueAndRequiredMargin(false, protocol);
        if (accountMarketValue > totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(account.id, protocol);

        (keeperFee, insuranceFundFee) = _computeLiquidationFees(
            accountMarketValue,
            notionalAmountClosed,
            fixFee,
            protocol.liquidationParams
        );

        account._updateBaseBalance(-(keeperFee + insuranceFundFee), protocol);
    }

    /// @notice computes the liquidation & liquidator price and insurance fund fee for token liquidation
    /// @param tokensToTrade amount of tokens to trade for liquidation
    /// @param poolId id of the pool to liquidate
    /// @param protocol set of all constants and token addresses
    function _getLiquidationPriceX128AndFee(
        int256 tokensToTrade,
        uint32 poolId,
        Protocol.Info storage protocol
    )
        internal
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        uint16 maintainanceMarginFactor = protocol.getMarginRatioFor(poolId, false);
        uint256 priceX128 = protocol.getVirtualCurrentPriceX128For(poolId);
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
    /// @param targetAccount is account being liquidated
    /// @param liquidatorAccount is account of liquidator
    /// @param poolId id of the rage trade pool
    /// @param tokensToTrade number of tokens to trade
    /// @param liquidationPriceX128 price at which tokens should be traded out
    /// @param liquidatorPriceX128 discounted price at which tokens should be given to liquidator
    /// @param fixFee is the fee to be given to liquidator to compensate for gas price
    /// @param protocol platform constants
    function _updateLiquidationAccounts(
        Account.Info storage targetAccount,
        Account.Info storage liquidatorAccount,
        uint32 poolId,
        int256 tokensToTrade,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 fixFee,
        Protocol.Info storage protocol
    ) internal returns (IClearingHouseStructures.BalanceAdjustments memory liquidatorBalanceAdjustments) {
        protocol.vPoolWrapperFor(poolId).updateGlobalFundingState();

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments = IClearingHouseStructures
            .BalanceAdjustments({
                vQuoteIncrease: -tokensToTrade.mulDiv(liquidationPriceX128, FixedPoint128.Q128) - fixFee,
                vTokenIncrease: tokensToTrade,
                traderPositionIncrease: tokensToTrade
            });

        targetAccount.tokenPositions.update(targetAccount.id, balanceAdjustments, poolId, protocol);
        emit TokenPositionChanged(
            targetAccount.id,
            poolId,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vQuoteIncrease
        );

        liquidatorBalanceAdjustments = IClearingHouseStructures.BalanceAdjustments({
            vQuoteIncrease: tokensToTrade.mulDiv(liquidatorPriceX128, FixedPoint128.Q128) + fixFee,
            vTokenIncrease: -tokensToTrade,
            traderPositionIncrease: -tokensToTrade
        });

        liquidatorAccount.tokenPositions.update(liquidatorAccount.id, liquidatorBalanceAdjustments, poolId, protocol);
        emit TokenPositionChanged(
            liquidatorAccount.id,
            poolId,
            liquidatorBalanceAdjustments.vTokenIncrease,
            liquidatorBalanceAdjustments.vQuoteIncrease
        );
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param targetAccount account to liquidate
    /// @param poolId id of the pool to liquidate
    /// @param protocol set of all constants and token addresses
    function liquidateTokenPosition(
        Account.Info storage targetAccount,
        Account.Info storage liquidatorAccount,
        uint16 liquidationBps,
        uint32 poolId,
        uint256 fixFee,
        Protocol.Info storage protocol,
        bool checkMargin
    )
        external
        returns (
            int256 insuranceFundFee,
            IClearingHouseStructures.BalanceAdjustments memory liquidatorBalanceAdjustments
        )
    {
        if (targetAccount.tokenPositions.isTokenRangeActive(poolId, protocol))
            revert InvalidLiquidationActiveRangePresent(poolId);

        {
            (int256 accountMarketValue, int256 totalRequiredMargin) = targetAccount._getAccountValueAndRequiredMargin(
                false,
                protocol
            );

            if (accountMarketValue > totalRequiredMargin) {
                revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
            }
        }

        int256 tokensToTrade;
        {
            VTokenPosition.Info storage vTokenPosition = targetAccount.tokenPositions.getTokenPosition(
                poolId,
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
                poolId,
                protocol
            );

            liquidatorBalanceAdjustments = _updateLiquidationAccounts(
                targetAccount,
                liquidatorAccount,
                poolId,
                tokensToTrade,
                liquidationPriceX128,
                liquidatorPriceX128,
                int256(fixFee),
                protocol
            );
        }
        {
            int256 accountMarketValueFinal = targetAccount._getAccountValue(protocol);

            if (accountMarketValueFinal < 0) {
                insuranceFundFee = accountMarketValueFinal;
                targetAccount._updateBaseBalance(-accountMarketValueFinal, protocol);
            }
        }

        if (checkMargin) liquidatorAccount._checkIfMarginAvailable(false, protocol);

        emit TokenPositionLiquidated(
            targetAccount.id,
            liquidatorAccount.id,
            poolId,
            liquidationBps,
            liquidationPriceX128,
            liquidatorPriceX128,
            fixFee,
            insuranceFundFee
        );
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param poolId id of the pool for the range
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        Account.Info storage account,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFeeAndFixFee,
        Protocol.Info storage protocol
    ) external {
        account.tokenPositions.removeLimitOrder(account.id, poolId, tickLower, tickUpper, protocol);

        account._updateBaseBalance(-int256(limitOrderFeeAndFixFee), protocol);
    }

    function getInfo(Account.Info storage account, Protocol.Info storage protocol)
        external
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            IClearingHouseStructures.DepositTokenView[] memory tokenDeposits,
            IClearingHouseStructures.VTokenPositionView[] memory tokenPositions
        )
    {
        owner = account.owner;
        tokenDeposits = account.tokenDeposits.getInfo(protocol);
        (vQuoteBalance, tokenPositions) = account.tokenPositions.getInfo(protocol);
    }

    function getNetPosition(
        Account.Info storage account,
        uint32 poolId,
        Protocol.Info storage protocol
    ) external view returns (int256 netPosition) {
        return account.tokenPositions.getNetPosition(poolId, protocol);
    }
}
