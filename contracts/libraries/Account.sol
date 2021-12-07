//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams, SwapParams } from './VTokenPositionSet.sol';
import { VTokenPosition } from './VTokenPosition.sol';

import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';

import { DepositTokenSet } from './DepositTokenSet.sol';

import { VPoolWrapper } from '../VPoolWrapper.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { SafeCast } from './uniswap/SafeCast.sol';
import { FullMath } from './FullMath.sol';
import { SignedMath } from './SignedMath.sol';

import { TickUtilLib } from './TickUtilLib.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { FixedPoint128 } from './uniswap/FixedPoint128.sol';
import { Constants } from '../utils/Constants.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { console } from 'hardhat/console.sol';

struct LiquidationParams {
    uint256 fixFee; //Same number of decimals as accountMarketValue
    uint256 minRequiredMargin;
    uint16 liquidationFeeFraction;
    uint16 tokenLiquidationPriceDeltaBps;
    uint16 insuranceFundFeeShareBps;
}

library Account {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;
    using DepositTokenSet for DepositTokenSet.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for VTokenAddress;
    using SafeCast for uint256;
    using FullMath for int256;
    using FullMath for uint256;

    using SignedMath for int256;
    using Account for Account.Info;

    error IneligibleLimitOrderRemoval();
    error InvalidTransactionNotEnoughMargin(int256 accountMarketValue, int256 totalRequiredMargin);
    error InvalidTransactionNotEnoughProfit(int256 totalProfit);
    error InvalidLiquidationAccountAbovewater(int256 accountMarketValue, int256 totalRequiredMargin);
    error InvalidTokenTradeAmount(int256 balance, int256 tokensToTrade);
    error InvalidLiquidationWrongSide(int256 totalRequiredMarginFinal, int256 totalRequiredMargin);
    error InvalidLiquidationActiveRangePresent(VTokenAddress vTokenAddress);

    event AccountCreated(address ownerAddress, uint256 accountNo);
    event DepositMargin(uint256 accountNo, VTokenAddress vTokenAddress, uint256 amount);
    event WithdrawMargin(uint256 accountNo, VTokenAddress vTokenAddress, uint256 amount);
    event WithdrawProfit(uint256 accountNo, uint256 amount);

    event TokenPositionChange(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int256 tokenAmountOut,
        int256 baseAmountOut
    );

    event LiquidityTokenPositionChange(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int256 tokenAmountOut
    );

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

    event FundingPayment(
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int256 amount
    );
    event LiquidityFee(uint256 accountNo, VTokenAddress vTokenAddress, int24 tickLower, int24 tickUpper, int256 amount);
    event ProtocolFeeWithdrawm(address wrapperAddress, uint256 feeAmount);

    event LiquidateRanges(
        uint256 accountNo,
        address keeperAddress,
        int256 liquidationFee,
        int256 keeperFee,
        int256 insuranceFundFee
    );
    event LiquidateTokenPosition(
        uint256 accountNo,
        uint256 liquidatorAccountNo,
        VTokenAddress vTokenAddress,
        uint16 liquidationBps,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        int256 insuranceFundFee
    );

    /// @dev some functions in token position and liquidity position want to
    ///  change user's balances. pointer to this memory struct is passed and
    ///  the inner methods update values. after the function exec these can
    ///  be applied to user's virtual balance.
    ///  example: see liquidityChange in LiquidityPosition
    struct BalanceAdjustments {
        int256 vBaseIncrease;
        int256 vTokenIncrease;
        int256 traderPositionIncrease;
    }

    struct Info {
        address owner;
        VTokenPositionSet.Set tokenPositions;
        DepositTokenSet.Info tokenDeposits;
    }

    /// @notice checks if 'account' is initialized
    /// @param account pointer to 'account' struct
    function isInitialized(Info storage account) internal view returns (bool) {
        return account.owner != address(0);
    }

    /// @notice increases deposit balance of 'vTokenAddress' by 'amount'
    /// @param account account to deposit balance into
    /// @param vTokenAddress address of token to deposit
    /// @param amount amount of token to deposit
    /// @param constants platform constants
    function addMargin(
        Info storage account,
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) internal {
        // collect
        // IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transferFrom(msg.sender, address(this), amount);
        // vBASE should be an immutable constant
        account.tokenDeposits.increaseBalance(vTokenAddress, amount, constants);
    }

    /// @notice reduces deposit balance of 'vTokenAddress' by 'amount'
    /// @param account account to deposit balance into
    /// @param vTokenAddress address of token to remove
    /// @param amount amount of token to remove
    /// @param constants platform constants
    function removeMargin(
        Info storage account,
        VTokenAddress vTokenAddress,
        uint256 amount,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal {
        account.tokenDeposits.decreaseBalance(vTokenAddress, amount, constants);

        account.checkIfMarginAvailable(true, vTokenAddresses, minRequiredMargin, constants);

        // process real token withdrawal
        // IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transfer(msg.sender, amount);
    }

    /// @notice removes 'amount' of profit generated in base token
    /// @param account account to remove profit from
    /// @param amount amount of profit(base token) to remove
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function removeProfit(
        Info storage account,
        uint256 amount,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            VTokenAddress.wrap(constants.VBASE_ADDRESS),
            constants
        );
        vTokenPosition.balance -= int256(amount);

        account.checkIfProfitAvailable(vTokenAddresses, constants);
        account.checkIfMarginAvailable(true, vTokenAddresses, minRequiredMargin, constants);

        // IERC20(RBASE_ADDRESS).transfer(msg.sender, amount);
    }

    function chargeFee(
        Info storage account,
        uint256 amount,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            VTokenAddress.wrap(constants.VBASE_ADDRESS),
            constants
        );
        vTokenPosition.balance -= int256(amount);
    }

    /// @notice returns market value and required margin for the account based on current market conditions
    /// @param account account to check
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    /// @return accountMarketValue total market value of all the positions and deposits
    /// @return totalRequiredMargin total margin required to keep the account above selected margin requirement (intial/maintainance)
    function getAccountValueAndRequiredMargin(
        Info storage account,
        bool isInitialMargin,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        // (int256 accountMarketValue, int256 totalRequiredMargin) = account
        //     .tokenPositions
        //     .getAllTokenPositionValueAndMargin(isInitialMargin, vTokenAddresses, constants);
        accountMarketValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        //TODO: Remove logs
        // console.log('accountMarketValue w/o deposits');
        // console.logInt(accountMarketValue);
        totalRequiredMargin = account.tokenPositions.getRequiredMargin(isInitialMargin, vTokenAddresses, constants);
        // console.log('totalRequiredMargin');
        // console.logInt(totalRequiredMargin);
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(vTokenAddresses, constants);
        // console.log('accountMarketValue with deposits');
        // console.logInt(accountMarketValue);
        totalRequiredMargin = totalRequiredMargin < int256(minRequiredMargin)
            ? int256(minRequiredMargin)
            : totalRequiredMargin;
        return (accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if market value > required margin
    /// @param account account to check
    /// @param isInitialMargin true to use initialMarginFactor and false to use maintainance margin factor for calcualtion of required margin
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function checkIfMarginAvailable(
        Info storage account,
        bool isInitialMargin,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
            isInitialMargin,
            vTokenAddresses,
            minRequiredMargin,
            constants
        );
        if (accountMarketValue < totalRequiredMargin)
            revert InvalidTransactionNotEnoughMargin(accountMarketValue, totalRequiredMargin);
    }

    /// @notice checks if profit is available to withdraw base token (token value of all positions > 0)
    /// @param account account to check
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function checkIfProfitAvailable(
        Info storage account,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal view {
        int256 totalPositionValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice swaps 'vTokenAddress' of token amount equal to 'vTokenAmount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @param account account to swap tokens for
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function swapToken(
        Info storage account,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // account fp bill
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.swapToken(vTokenAddress, swapParams, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, minRequiredMargin, constants);
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if liquidityDelta>0 then liquidity is added and if liquidityChange<0 then liquidity is removed
    /// @param account account to change liquidity for
    /// @param vTokenAddress address of token to swap
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta and limit order type
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidityChange(
        Info storage account,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal returns (int256 notionalValue) {
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants);

        // mint/burn tokens + fee + funding payment
        notionalValue = account.tokenPositions.liquidityChange(vTokenAddress, liquidityChangeParams, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, minRequiredMargin, constants);
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if liquidity>0 then the swap is a long or close short and if vTokenNotional<0 then swap is a short or close long
    /// @param accountMarketValue market value of account
    /// @param fixFee fixed fees to be paid
    /// @param liquidationFee parameters including lower tick, upper tick, liquidity delta and limit order type
    /// @return keeperFee map of vTokenAddresses allowed on the platform
    /// @return insuranceFundFee poolwrapper for token
    function computeLiquidationFees(
        int256 accountMarketValue,
        int256 fixFee,
        int256 liquidationFee,
        LiquidationParams memory liquidationParams
    ) internal pure returns (int256 keeperFee, int256 insuranceFundFee) {
        keeperFee = liquidationFee.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4) + fixFee;
        if (accountMarketValue - fixFee - liquidationFee < 0) {
            insuranceFundFee = accountMarketValue - fixFee - liquidationFee + keeperFee;
        } else {
            insuranceFundFee = liquidationFee - keeperFee;
        }
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidateLiquidityPositions(
        Info storage account,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        LiquidationParams memory liquidationParams,
        uint256 minRequiredMargin,
        Constants memory constants
    ) internal returns (int256 keeperFee, int256 insuranceFundFee) {
        //check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 notionalAmountClosed;
        int256 fixFee;

        (accountMarketValue, totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
            false,
            vTokenAddresses,
            minRequiredMargin,
            constants
        );
        if (accountMarketValue > totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, constants);

        int256 liquidationFee = (notionalAmountClosed * int256(int16(liquidationParams.liquidationFeeFraction)));
        (keeperFee, insuranceFundFee) = computeLiquidationFees(
            accountMarketValue,
            fixFee,
            liquidationFee,
            liquidationParams
        );

        account.chargeFee(uint256(keeperFee + insuranceFundFee), constants);
    }

    function getLiquidationPriceX128(
        int256 tokenBalance,
        VTokenAddress vTokenAddress,
        LiquidationParams memory liquidationParams,
        Constants memory constants
    ) internal view returns (uint256 liquidationPriceX128, uint256 liquidatorPriceX128) {
        uint16 maintainanceMarginFactor = vTokenAddress.getMarginRatio(false, constants);
        uint256 priceX128 = vTokenAddress.getVirtualTwapPriceX128(constants);
        uint256 priceDeltaX128 = priceX128.mulDiv(liquidationParams.tokenLiquidationPriceDeltaBps, 1e4).mulDiv(
            maintainanceMarginFactor,
            1e5
        );
        if (tokenBalance > 0) {
            liquidationPriceX128 = priceX128 - priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 -
                priceDeltaX128.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4);
        } else {
            liquidationPriceX128 = priceX128 + priceDeltaX128;
            liquidatorPriceX128 =
                priceX128 +
                priceDeltaX128.mulDiv(1e4 - liquidationParams.insuranceFundFeeShareBps, 1e4);
        }
    }

    function updateLiquidationAccounts(
        Info storage account,
        Info storage liquidatorAccount,
        VTokenAddress vTokenAddress,
        int256 tokensToTrade,
        uint256 liquidationPriceX128,
        uint256 liquidatorPriceX128,
        Constants memory constants
    ) internal {
        BalanceAdjustments memory balanceAdjustments = BalanceAdjustments(
            -tokensToTrade.mulDiv(liquidationPriceX128, FixedPoint128.Q128),
            tokensToTrade,
            tokensToTrade
        );

        account.tokenPositions.update(balanceAdjustments, vTokenAddress, constants);
        emit Account.TokenPositionChange(
            account.tokenPositions.accountNo,
            vTokenAddress,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vBaseIncrease
        );

        balanceAdjustments = BalanceAdjustments(
            tokensToTrade.mulDiv(liquidatorPriceX128, FixedPoint128.Q128),
            -tokensToTrade,
            -tokensToTrade
        );

        liquidatorAccount.tokenPositions.update(balanceAdjustments, vTokenAddress, constants);
        emit Account.TokenPositionChange(
            liquidatorAccount.tokenPositions.accountNo,
            vTokenAddress,
            balanceAdjustments.vTokenIncrease,
            balanceAdjustments.vBaseIncrease
        );
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidateTokenPosition(
        Info storage account,
        Info storage liquidatorAccount,
        uint16 liquidationBps,
        VTokenAddress vTokenAddress,
        LiquidationParams memory liquidationParams,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256 insuranceFundFee) {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            vTokenAddress,
            constants
        );

        if (vTokenPosition.liquidityPositions.active[0] != 0)
            revert InvalidLiquidationActiveRangePresent(vTokenAddress);

        {
            {
                (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
                    false,
                    vTokenAddresses,
                    liquidationParams.minRequiredMargin,
                    constants
                );

                if (accountMarketValue > totalRequiredMargin) {
                    revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
                }
            }

            int256 tokensToTrade = -vTokenPosition.balance.mulDiv(liquidationBps, 1e4);

            (uint256 liquidationPriceX128, uint256 liquidatorPriceX128) = getLiquidationPriceX128(
                vTokenPosition.balance,
                vTokenAddress,
                liquidationParams,
                constants
            );

            insuranceFundFee = tokensToTrade.mulDiv(liquidatorPriceX128 - liquidationPriceX128, FixedPoint128.Q128);

            updateLiquidationAccounts(
                account,
                liquidatorAccount,
                vTokenAddress,
                tokensToTrade,
                liquidationPriceX128,
                liquidatorPriceX128,
                constants
            );
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
        int256 accountMarketValueFinal = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);

        if (accountMarketValueFinal < 0) {
            insuranceFundFee = accountMarketValueFinal.abs();
        }
        liquidatorAccount.checkIfMarginAvailable(
            false,
            vTokenAddresses,
            liquidationParams.minRequiredMargin,
            constants
        );
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param constants platform constants
    function removeLimitOrder(
        Info storage account,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFee,
        Constants memory constants
    ) internal {
        int24 currentTick = VTokenAddress.wrap(vTokenAddress).getVirtualTwapTick(constants);
        LiquidityPosition.Info storage position = account
            .tokenPositions
            .getTokenPosition(vTokenAddress, constants)
            .liquidityPositions
            .getLiquidityPosition(tickLower, tickUpper);

        if (
            (currentTick >= tickUpper && position.limitOrderType == LimitOrderType.UPPER_LIMIT) ||
            (currentTick <= tickLower && position.limitOrderType == LimitOrderType.LOWER_LIMIT)
        ) {
            // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
            account.tokenPositions.closeLiquidityPosition(vTokenAddress, position, constants);
        } else {
            revert IneligibleLimitOrderRemoval();
        }

        account.chargeFee(limitOrderFee, constants);
    }
}
