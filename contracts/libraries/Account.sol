//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { DepositTokenSet } from './DepositTokenSet.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { VTokenPositionSet, LiquidityChangeParams, SwapParams } from './VTokenPositionSet.sol';
import { RealTokenLib } from './RealTokenLib.sol';
import { AccountStorage } from '../ClearingHouseStorage.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

/// @notice parameters to be used for liquidation
/// @param fixFee specifies the fixFee to be given for successful liquidation
/// @param minRequiredMargin specifies the minimum required margin threshold
/// @param liquidationFeeFraction specifies the percentage of notional value liquidated to be charged as liquidation fees
/// @param tokenLiquidationPriceDeltaBps specifies the price delta from current perp price at which the liquidator should get the position
/// @param insuranceFundFeeShare specifies the fee share for insurance fund out of the total liquidation fee
struct LiquidationParams {
    uint16 liquidationFeeFraction;
    uint16 tokenLiquidationPriceDeltaBps;
    uint16 insuranceFundFeeShareBps;
}

library Account {
    using Account for Account.Info;
    using DepositTokenSet for DepositTokenSet.Info;
    using FullMath for uint256;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;

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
    /// @param vTokenAddress shows the token address for which range is active
    error InvalidLiquidationActiveRangePresent(VTokenAddress vTokenAddress);

    /// @notice denotes new account creation
    /// @param ownerAddress wallet address of account owner
    /// @param accountNo serial number of the account
    event AccountCreated(address ownerAddress, uint256 accountNo);

    /// @notice denotes deposit of margin
    /// @param accountNo serial number of the account
    /// @param vTokenAddress token in which margin is deposited
    /// @param amount amount of tokens deposited
    event DepositMargin(uint256 accountNo, VTokenAddress vTokenAddress, uint256 amount);

    /// @notice denotes withdrawal of margin
    /// @param accountNo serial number of the account
    /// @param vTokenAddress token in which margin is withdrawn
    /// @param amount amount of tokens withdrawn
    event WithdrawMargin(uint256 accountNo, VTokenAddress vTokenAddress, uint256 amount);

    /// @notice denotes withdrawal of profit in base token
    /// @param accountNo serial number of the account
    /// @param amount amount of profit withdrawn
    event WithdrawProfit(uint256 accountNo, uint256 amount);

    /// @notice denotes token position change
    /// @param accountNo serial number of the account
    /// @param vTokenAddress address of token whose position was taken
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event TokenPositionChange(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes token position change due to liquidity add/remove
    /// @param accountNo serial number of the account
    /// @param vTokenAddress address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    event LiquidityTokenPositionChange(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int256 tokenAmountOut
    );

    /// @notice denotes liquidity add/remove
    /// @param accountNo serial number of the account
    /// @param vTokenAddress address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param liquidityDelta change in liquidity value
    /// @param limitOrderType the type of range position
    /// @param tokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @param baseAmountOut amount of base tokens that account received (positive) or paid (negative)
    event LiquidityChange(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        LimitOrderType limitOrderType,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    /// @notice denotes funding payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountNo serial number of the account
    /// @param vTokenAddress address of token for which funding was paid
    /// @param tickLower lower tick of the range for which funding was paid
    /// @param tickUpper upper tick of the range for which funding was paid
    /// @param amount amount of funding paid (negative) or received (positive)
    event FundingPayment(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );

    /// @notice denotes fee payment for a range / token position
    /// @dev for a token position tickLower = tickUpper = 0
    /// @param accountNo serial number of the account
    /// @param vTokenAddress address of token for which fee was paid
    /// @param tickLower lower tick of the range for which fee was paid
    /// @param tickUpper upper tick of the range for which fee was paid
    /// @param amount amount of fee paid (negative) or received (positive)
    event LiquidityFee(uint256 accountNo, VTokenAddress vTokenAddress, int24 tickLower, int24 tickUpper, int256 amount);

    /// @notice denotes protocol fee withdrawal from a pool wrapper
    /// @param wrapperAddress address of token for which fee was paid
    /// @param feeAmount amount of protocol fee which was withdrawn
    event ProtocolFeeWithdrawm(address wrapperAddress, uint256 feeAmount);

    /// @notice denotes range position liquidation event
    /// @dev all range positions are liquidated and the current tokens inside the range are added in as token positions to the account
    /// @param accountNo serial number of the account
    /// @param keeperAddress address of keeper who performed the liquidation
    /// @param liquidationFee total liquidation fee charged to the account
    /// @param keeperFee total liquidaiton fee paid to the keeper (positive only)
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enought to cover the fee)
    event LiquidateRanges(
        uint256 accountNo,
        address keeperAddress,
        int256 liquidationFee,
        int256 keeperFee,
        int256 insuranceFundFee
    );

    /// @notice denotes token position liquidation event
    /// @dev the selected token position is take from the current account and moved to liquidatorAccount at a discounted prive to current pool price
    /// @param accountNo serial number of the account
    /// @param liquidatorAccountNo  account which performed the liquidation
    /// @param vTokenAddress address of token for whose position was liquidated
    /// @param liquidationBps the fraction of current position which was liquidated in bps
    /// @param liquidationPriceX128 price at which liquidation was performed
    /// @param liquidatorPriceX128 discounted price at which tokens were transferred to the liquidator account
    /// @param insuranceFundFee total liquidaiton fee paid to the insurance fund (can be negative in case the account is not enough to cover the fee)
    event LiquidateTokenPosition(
        uint256 accountNo,
        uint256 liquidatorAccountNo,
        VTokenAddress vTokenAddress,
        uint16 liquidationBps,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 insuranceFundFee
    );

    /// @notice parameters to be used for account balance update
    /// @param vBaseIncrease specifies the increase in base balance
    /// @param vTokenIncrease specifies the increase in token balance
    /// @param traderPositionIncrease specifies the increase in trader position
    struct BalanceAdjustments {
        int256 vBaseIncrease;
        int256 vTokenIncrease;
        int256 traderPositionIncrease;
    }

    /// @notice account info
    /// @param owner specifies the account owner
    /// @param tokenPositions is set of all open token positions
    /// @param tokenDeposits is set of all deposits
    struct Info {
        address owner;
        VTokenPositionSet.Set tokenPositions;
        DepositTokenSet.Info tokenDeposits;
        uint256[100] emptySlots; // reserved for adding variables when upgrading logic
    }

    /// @notice checks if 'account' is initialized
    /// @param account pointer to 'account' struct
    function isInitialized(Info storage account) internal view returns (bool) {
        return account.owner != address(0);
    }

    /// @notice updates the base balance for 'account' by 'amount'
    /// @param account pointer to 'account' struct
    /// @param amount amount of balance to update
    /// @param constants platform constants
    function updateBaseBalance(
        Info storage account,
        int256 amount,
        Constants memory constants
    ) internal returns (BalanceAdjustments memory balanceAdjustments) {
        balanceAdjustments = BalanceAdjustments(amount, 0, 0);
        account.tokenPositions.update(balanceAdjustments, VTokenAddress.wrap(constants.VBASE_ADDRESS), constants);
    }

    /// @notice increases deposit balance of 'vTokenAddress' by 'amount'
    /// @param account account to deposit balance into
    /// @param vTokenAddress address of token to deposit
    /// @param amount amount of token to deposit
    /// @param accountStorage set of all constants and token addresses
    function addMargin(
        Info storage account,
        VTokenAddress vTokenAddress,
        uint256 amount,
        AccountStorage storage accountStorage
    ) external {
        // vBASE should be an immutable constant
        account.tokenDeposits.increaseBalance(vTokenAddress, amount, accountStorage.constants);
    }

    /// @notice reduces deposit balance of 'vTokenAddress' by 'amount'
    /// @param account account to deposit balance into
    /// @param vTokenAddress address of token to remove
    /// @param amount amount of token to remove
    /// @param accountStorage set of all constants and token addresses
    function removeMargin(
        Info storage account,
        VTokenAddress vTokenAddress,
        uint256 amount,
        AccountStorage storage accountStorage
    ) external {
        account.tokenDeposits.decreaseBalance(vTokenAddress, amount, accountStorage.constants);

        account.checkIfMarginAvailable(true, accountStorage);
    }

    /// @notice removes 'amount' of profit generated in base token
    /// @param account account to remove profit from
    /// @param amount amount of profit(base token) to remove
    /// @param accountStorage set of all constants and token addresses
    function removeProfit(
        Info storage account,
        uint256 amount,
        AccountStorage storage accountStorage
    ) external {
        account.updateBaseBalance(-int256(amount), accountStorage.constants);

        account.checkIfProfitAvailable(accountStorage);
        account.checkIfMarginAvailable(true, accountStorage);
    }

    /// @notice returns market value and required margin for the account based on current market conditions
    /// @dev (In case requiredMargin < minRequiredMargin then requiredMargin = minRequiredMargin)
    /// @param account account to check
    /// @param isInitialMargin true to use initial margin factor and false to use maintainance margin factor for calcualtion of required margin
    /// @param accountStorage set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    /// @return totalRequiredMargin total margin required to keep the account above selected margin requirement (intial/maintainance)
    function getAccountValueAndRequiredMargin(
        Info storage account,
        bool isInitialMargin,
        AccountStorage storage accountStorage
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        accountMarketValue = account.getAccountValue(accountStorage);

        totalRequiredMargin = account.tokenPositions.getRequiredMargin(
            isInitialMargin,
            accountStorage.vTokenAddresses,
            accountStorage.constants
        );
        if (!account.tokenPositions.isEmpty()) {
            totalRequiredMargin = totalRequiredMargin < int256(accountStorage.minRequiredMargin)
                ? int256(accountStorage.minRequiredMargin)
                : totalRequiredMargin;
        }
        return (accountMarketValue, totalRequiredMargin);
    }

    /// @notice returns market value for the account based on current market conditions
    /// @param account account to check
    /// @param accountStorage set of all constants and token addresses
    /// @return accountMarketValue total market value of all the positions (token ) and deposits
    function getAccountValue(Info storage account, AccountStorage storage accountStorage)
        internal
        view
        returns (int256 accountMarketValue)
    {
        accountMarketValue = account.tokenPositions.getAccountMarketValue(
            accountStorage.vTokenAddresses,
            accountStorage.constants
        );
        //TODO: Remove logs
        // console.log('accountMarketValue w/o deposits');
        // console.logInt(accountMarketValue);
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(
            accountStorage.vTokenAddresses,
            accountStorage.constants
        );
        // console.log('accountMarketValue with deposits');
        // console.logInt(accountMarketValue);
        return (accountMarketValue);
    }

    /// @notice checks if market value > required margin else revert with InvalidTransactionNotEnoughMargin
    /// @param account account to check
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param accountStorage set of all constants and token addresses
    function checkIfMarginAvailable(
        Info storage account,
        bool isInitialMargin,
        AccountStorage storage accountStorage
    ) internal view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
            isInitialMargin,
            accountStorage
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if profit is available to withdraw base token (token value of all positions > 0) else revert with InvalidTransactionNotEnoughProfit
    /// @param account account to check
    /// @param accountStorage set of all constants and token addresses
    function checkIfProfitAvailable(Info storage account, AccountStorage storage accountStorage) internal view {
        int256 totalPositionValue = account.tokenPositions.getAccountMarketValue(
            accountStorage.vTokenAddresses,
            accountStorage.constants
        );
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice swaps 'vTokenAddress' of token amount equal to 'swapParams.amount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @notice isNotional specifies whether the amount represents token amount (false) or base amount(true)
    /// @notice isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
    /// @notice sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
    /// @param account account to swap tokens for
    /// @param vTokenAddress address of the token to swap
    /// @param swapParams parameters for the swap (Includes - amount, sqrtPriceLimit, isNotional, isPartialAllowed)
    /// @param accountStorage set of all constants and token addresses
    function swapToken(
        Info storage account,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        AccountStorage storage accountStorage
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // account fp bill
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.swapToken(
            vTokenAddress,
            swapParams,
            accountStorage.constants
        );

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, accountStorage);
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if 'liquidityDelta'>0 then liquidity is added and if 'liquidityChange'<0 then liquidity is removed
    /// @notice the liquidity change is reverted if the sqrt price at the time of execution is beyond 'slippageToleranceBps' of 'sqrtPriceCurrent' supplied
    /// @notice whenever liquidity change is done the internal token position is taken out. If 'closeTokenPosition' is true this is swapped out else it is added to the current token position
    /// @param account account to change liquidity
    /// @param vTokenAddress address of token to swap
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta, sqrtPriceCurrent, slippageToleranceBps, closeTokenPosition, limit order type
    /// @param accountStorage set of all constants and token addresses
    function liquidityChange(
        Info storage account,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        AccountStorage storage accountStorage
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants);

        // mint/burn tokens + fee + funding payment
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.liquidityChange(
            vTokenAddress,
            liquidityChangeParams,
            accountStorage.constants
        );

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, accountStorage);
    }

    /// @notice computes keeper fee and insurance fund fee in case of liquidity position liquidation
    /// @dev keeperFee = liquidationFee*(1-insuranceFundFeeShare)+fixFee
    /// @dev insuranceFundFee = accountMarketValue - keeperFee (if accountMarketValue is not enough to cover the fees) else insurancFundFee = liquidationFee - keeperFee + fixFee
    /// @param accountMarketValue market value of account
    /// @param liquidationFee total liquidation fee to be charged to the account in case of an on time liquidation
    /// @param liquidationParams parameters including fixFee, insuranceFundFeeShareBps
    /// @return keeperFee map of vTokenAddresses allowed on the platform
    /// @return insuranceFundFee poolwrapper for token
    function computeLiquidationFees(
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
    /// @param accountStorage set of all constants and token addresses
    function liquidateLiquidityPositions(
        Info storage account,
        uint256 fixFee,
        AccountStorage storage accountStorage
    ) external returns (int256 keeperFee, int256 insuranceFundFee) {
        //check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 notionalAmountClosed;

        (accountMarketValue, totalRequiredMargin) = account.getAccountValueAndRequiredMargin(false, accountStorage);
        if (accountMarketValue > totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(
            accountStorage.vTokenAddresses,
            accountStorage.constants
        );

        int256 liquidationFee = notionalAmountClosed.mulDiv(
            accountStorage.liquidationParams.liquidationFeeFraction,
            1e5
        );
        (keeperFee, insuranceFundFee) = computeLiquidationFees(
            accountMarketValue,
            liquidationFee,
            fixFee,
            accountStorage.liquidationParams
        );

        account.updateBaseBalance(-(keeperFee + insuranceFundFee), accountStorage.constants);
    }

    /// @notice computes the liquidation & liquidator price and insurance fund fee for token liquidation
    /// @param tokensToTrade account to liquidate
    /// @param vTokenAddress map of vTokenAddresses allowed on the platform
    /// @param accountStorage set of all constants and token addresses
    function getLiquidationPriceX128AndFee(
        int256 tokensToTrade,
        VTokenAddress vTokenAddress,
        AccountStorage storage accountStorage
    )
        internal
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        uint16 maintainanceMarginFactor = vTokenAddress.getMarginRatio(false, accountStorage.constants);
        uint256 priceX128 = vTokenAddress.getVirtualCurrentPriceX128(accountStorage.constants);
        // console.log('PriceX128');
        // console.log(priceX128);
        // console.log(
        //     'tokenLiquidationPriceDeltaBps',
        //     liquidationParams.tokenLiquidationPriceDeltaBps,
        //     'maintainanceMarginFactor',
        //     maintainanceMarginFactor
        // );
        uint256 priceDeltaX128 = priceX128
            .mulDiv(accountStorage.liquidationParams.tokenLiquidationPriceDeltaBps, 1e4)
            .mulDiv(maintainanceMarginFactor, 1e5);
        if (tokensToTrade < 0) {
            liquidationPriceX128 = priceX128 - priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 -
                priceDeltaX128.mulDiv(1e4 - accountStorage.liquidationParams.insuranceFundFeeShareBps, 1e4);
            insuranceFundFee = -tokensToTrade.mulDiv(liquidatorPriceX128 - liquidationPriceX128, FixedPoint128.Q128);
        } else {
            liquidationPriceX128 = priceX128 + priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 +
                priceDeltaX128.mulDiv(1e4 - accountStorage.liquidationParams.insuranceFundFeeShareBps, 1e4);
            insuranceFundFee = tokensToTrade.mulDiv(liquidationPriceX128 - liquidatorPriceX128, FixedPoint128.Q128);
        }
    }

    /// @notice exchanges token position between account (at liquidationPrice) and liquidator account (at liquidator price)
    /// @notice also charges fixFee from the account and pays to liquidator
    /// @param account is account being liquidated
    /// @param liquidatorAccount is account of liquidator
    /// @param vTokenAddress map of vTokenAddresses allowed on the platform
    /// @param tokensToTrade number of tokens to trade
    /// @param liquidationPriceX128 price at which tokens should be traded out
    /// @param liquidatorPriceX128 discounted price at which tokens should be given to liquidator
    /// @param fixFee is the fee to be given to liquidator to compensate for gas price
    /// @param constants platform constants
    function updateLiquidationAccounts(
        Info storage account,
        Info storage liquidatorAccount,
        VTokenAddress vTokenAddress,
        int256 tokensToTrade,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 fixFee,
        Constants memory constants
    ) internal returns (BalanceAdjustments memory liquidatorBalanceAdjustments) {
        BalanceAdjustments memory balanceAdjustments = BalanceAdjustments({
            vBaseIncrease: -tokensToTrade.mulDiv(liquidationPriceX128, FixedPoint128.Q128) - fixFee,
            vTokenIncrease: tokensToTrade,
            traderPositionIncrease: tokensToTrade
        });

        // console.log('Liquidation Account Update Values');
        // console.logInt(balanceAdjustments.vBaseIncrease);
        // console.logInt(balanceAdjustments.vTokenIncrease);
        // console.logInt(balanceAdjustments.traderPositionIncrease);

        account.tokenPositions.update(balanceAdjustments, vTokenAddress, constants);
        emit Account.TokenPositionChange(
            account.tokenPositions.accountNo,
            vTokenAddress,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vBaseIncrease
        );

        balanceAdjustments = BalanceAdjustments({
            vBaseIncrease: tokensToTrade.mulDiv(liquidatorPriceX128, FixedPoint128.Q128) + fixFee,
            vTokenIncrease: -tokensToTrade,
            traderPositionIncrease: -tokensToTrade
        });

        // console.log('Liquidator Account Update Values');
        // console.logInt(balanceAdjustments.vBaseIncrease);
        // console.logInt(balanceAdjustments.vTokenIncrease);
        // console.logInt(balanceAdjustments.traderPositionIncrease);

        liquidatorAccount.tokenPositions.update(balanceAdjustments, vTokenAddress, constants);
        emit Account.TokenPositionChange(
            liquidatorAccount.tokenPositions.accountNo,
            vTokenAddress,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vBaseIncrease
        );

        return balanceAdjustments;
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param accountStorage set of all constants and token addresses
    function liquidateTokenPosition(
        Info storage account,
        Info storage liquidatorAccount,
        uint16 liquidationBps,
        VTokenAddress vTokenAddress,
        uint256 fixFee,
        AccountStorage storage accountStorage
    ) external returns (int256 insuranceFundFee, BalanceAdjustments memory liquidatorBalanceAdjustments) {
        // VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
        //     vTokenAddress,
        //     false,
        //     constants
        // );

        if (account.tokenPositions.getIsTokenRangeActive(vTokenAddress, accountStorage.constants))
            revert InvalidLiquidationActiveRangePresent(vTokenAddress);

        {
            (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
                false,
                accountStorage
            );
            // console.log('########## Beginning of Liquidation ##############');
            // console.log('Account Market Value');
            // console.logInt(accountMarketValue);
            // console.log('Required Margin');
            // console.logInt(totalRequiredMargin);

            if (accountMarketValue > totalRequiredMargin) {
                revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
            }
        }

        int256 tokensToTrade;
        {
            VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
                vTokenAddress,
                false,
                accountStorage.constants
            );
            tokensToTrade = -vTokenPosition.balance.mulDiv(liquidationBps, 1e4);
        }

        uint256 liquidationPriceX128;
        uint256 liquidatorPriceX128;
        {
            // console.log('Tokens To Trade');
            // console.logInt(tokensToTrade);

            (liquidationPriceX128, liquidatorPriceX128, insuranceFundFee) = getLiquidationPriceX128AndFee(
                tokensToTrade,
                vTokenAddress,
                accountStorage
            );

            // console.log('LiquidationPriceX128');
            // console.log(liquidationPriceX128);
            // console.log('LiquidatorPriceX128');
            // console.log(liquidatorPriceX128);
            // console.log('Insurnace Fund Fee');
            // console.logInt(insuranceFundFee);
            liquidatorBalanceAdjustments = updateLiquidationAccounts(
                account,
                liquidatorAccount,
                vTokenAddress,
                tokensToTrade,
                liquidationPriceX128,
                liquidatorPriceX128,
                int256(fixFee),
                accountStorage.constants
            );
        }
        {
            int256 accountMarketValueFinal = account.getAccountValue(accountStorage);

            if (accountMarketValueFinal < 0) {
                insuranceFundFee = accountMarketValueFinal;
                account.updateBaseBalance(-accountMarketValueFinal, accountStorage.constants);
            }
        }
        // console.log('#############  Insurance Fund Fee  ##################');
        // console.logInt(insuranceFundFee);
        liquidatorAccount.checkIfMarginAvailable(false, accountStorage);
        emit Account.LiquidateTokenPosition(
            account.tokenPositions.accountNo,
            liquidatorAccount.tokenPositions.accountNo,
            vTokenAddress,
            liquidationBps,
            liquidationPriceX128,
            liquidatorPriceX128,
            insuranceFundFee
        );
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param vTokenAddress address of token for the range
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param constants platform constants
    function removeLimitOrder(
        Info storage account,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFeeAndFixFee,
        Constants memory constants
    ) external {
        account.tokenPositions.removeLimitOrder(vTokenAddress, tickLower, tickUpper, constants);

        account.updateBaseBalance(-int256(limitOrderFeeAndFixFee), constants);
    }
}
