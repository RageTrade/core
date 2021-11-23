//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from './VTokenPositionSet.sol';
import { VTokenPosition } from './VTokenPosition.sol';

import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';

import { DepositTokenSet } from './DepositTokenSet.sol';

import { VPoolWrapper } from '../VPoolWrapper.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { SafeCast } from './uniswap/SafeCast.sol';
import { FullMath } from './FullMath.sol';

import { TickUtilLib } from './TickUtilLib.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Constants } from '../utils/Constants.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

struct LiquidationParams {
    uint16 liquidationFeeFraction; //*e5
    uint256 liquidationMinSizeBaseAmount; // Same number of decimals as in accountMarketValue
    uint8 targetMarginRatio; //*e1
    uint256 fixFee; //Same number of decimals as accountMarketValue
}

library Account {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;
    using DepositTokenSet for DepositTokenSet.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for VTokenAddress;
    using SafeCast for uint256;
    using FullMath for int256;

    using Account for Account.Info;

    error IneligibleLimitOrderRemoval();
    error InvalidTransactionNotEnoughMargin(int256 accountMarketValue, int256 totalRequiredMargin);
    error InvalidTransactionNotEnoughProfit(int256 totalProfit);
    error InvalidLiquidationAccountAbovewater(int256 accountMarketValue, int256 totalRequiredMargin);
    error InvalidTokenTradeAmount(int256 balance, int256 tokensToTrade);
    error InvalidLiquidationWrongSide(int256 totalRequiredMarginFinal, int256 totalRequiredMargin);

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
        address vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) internal {
        // collect
        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transferFrom(msg.sender, address(this), amount);
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
        address vTokenAddress,
        uint256 amount,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.tokenDeposits.decreaseBalance(vTokenAddress, amount, constants);

        account.checkIfMarginAvailable(true, vTokenAddresses, constants);

        // process real token withdrawal
        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transfer(msg.sender, amount);
    }

    /// @notice removes 'amount' of profit generated in base token
    /// @param account account to remove profit from
    /// @param amount amount of profit(base token) to remove
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function removeProfit(
        Info storage account,
        uint256 amount,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            constants.VBASE_ADDRESS,
            constants
        );
        vTokenPosition.balance -= int256(amount);

        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
        account.checkIfProfitAvailable(vTokenAddresses, constants);

        // IERC20(RBASE_ADDRESS).transfer(msg.sender, amount);
    }

    function chargeFee(
        Info storage account,
        uint256 amount,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            constants.VBASE_ADDRESS,
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
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        // (int256 accountMarketValue, int256 totalRequiredMargin) = account
        //     .tokenPositions
        //     .getAllTokenPositionValueAndMargin(isInitialMargin, vTokenAddresses, constants);
        accountMarketValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        totalRequiredMargin = account.tokenPositions.getRequiredMargin(isInitialMargin, vTokenAddresses, constants);
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(vTokenAddresses, constants);
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
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
            isInitialMargin,
            vTokenAddresses,
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
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view {
        int256 totalPositionValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    /// @notice swaps 'vTokenAddress' of token amount equal to 'vTokenAmount'
    /// @notice if vTokenAmount>0 then the swap is a long or close short and if vTokenAmount<0 then swap is a short or close long
    /// @param account account to swap tokens for
    /// @param vTokenAddress address of token to swap
    /// @param vTokenAmount amount of token to swap
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param wrapper poolwrapper for token
    /// @param constants platform constants
    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // account fp bill
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.swapTokenAmount(
            vTokenAddress,
            vTokenAmount,
            wrapper,
            constants
        );

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

    /// @notice swaps 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if vTokenNotional>0 then the swap is a long or close short and if vTokenNotional<0 then swap is a short or close long
    /// @param account account to swap tokens for
    /// @param vTokenAddress address of token to swap
    /// @param vTokenNotional notional value of token to swap (>0 => long or close short and <0 => short or close long)
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param wrapper poolwrapper for token
    /// @param constants platform constants
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // account fp bill
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. and send to the pool
        (vTokenAmountOut, vBaseAmountOut) = account.tokenPositions.swapTokenNotional(
            vTokenAddress,
            vTokenNotional,
            wrapper,
            constants
        );

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

    /// @notice swaps 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if vTokenNotional>0 then the swap is a long or close short and if vTokenNotional<0 then swap is a short or close long
    /// @param account account to swap tokens for
    /// @param vTokenAddress address of token to swap
    /// @param vTokenAmount amount of token to swap (>0 => long or close short and <0 => short or close long)
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            account.swapTokenAmount(
                vTokenAddress,
                vTokenAmount,
                vTokenAddresses,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    /// @notice swaps 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if vTokenNotional>0 then the swap is a long or close short and if vTokenNotional<0 then swap is a short or close long
    /// @param account account to swap tokens for
    /// @param vTokenAddress address of token to swap
    /// @param vTokenNotional notional value of token to swap (>0 => long or close short and <0 => short or close long)
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            account.swapTokenNotional(
                vTokenAddress,
                vTokenNotional,
                vTokenAddresses,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if liquidityDelta>0 then liquidity is added and if liquidityChange<0 then liquidity is removed
    /// @param account account to change liquidity for
    /// @param vTokenAddress address of token to swap
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta and limit order type
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param wrapper poolwrapper for token
    /// @param constants platform constants
    function liquidityChange(
        Info storage account,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants);

        // mint/burn tokens + fee + funding payment
        account.tokenPositions.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if liquidityDelta>0 then liquidity is added and if liquidityChange<0 then liquidity is removed
    /// @param account account to swap tokenschange liquidity for
    /// @param vTokenAddress address of token to swap
    /// @param liquidityChangeParams parameters including lower tick, upper tick, liquidity delta and limit order type
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidityChange(
        Info storage account,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.liquidityChange(
            vTokenAddress,
            liquidityChangeParams,
            vTokenAddresses,
            VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
            constants
        );
    }

    /// @notice changes range liquidity 'vTokenAddress' of market value equal to 'vTokenNotional'
    /// @notice if liquidity>0 then the swap is a long or close short and if vTokenNotional<0 then swap is a short or close long
    /// @param accountMarketValue market value of account
    /// @param fixFee fixed fees to be paid
    /// @param liquidationFeeHalf parameters including lower tick, upper tick, liquidity delta and limit order type
    /// @return keeperFees map of vTokenAddresses allowed on the platform
    /// @return insuranceFundFees poolwrapper for token
    function computeLiquidationFees(
        int256 accountMarketValue,
        int256 fixFee,
        int256 liquidationFeeHalf
    ) internal pure returns (int256 keeperFees, int256 insuranceFundFees) {
        keeperFees = liquidationFeeHalf + fixFee;
        if (accountMarketValue - fixFee - 2 * liquidationFeeHalf < 0) {
            insuranceFundFees = accountMarketValue - fixFee - liquidationFeeHalf;
        } else {
            insuranceFundFees = liquidationFeeHalf;
        }
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param liquidationFeeFraction fraction of notional closed to be liquidated
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param wrapper poolwrapper for token
    /// @param constants platform constants
    function liquidateLiquidityPositions(
        Info storage account,
        uint16 liquidationFeeFraction,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
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
            constants
        );
        if (accountMarketValue < totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, wrapper, constants);

        int256 liquidationFeeHalf = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
        (keeperFee, insuranceFundFee) = computeLiquidationFees(accountMarketValue, fixFee, liquidationFeeHalf);

        account.chargeFee(uint256(keeperFee + insuranceFundFee), constants);
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param liquidationFeeFraction fraction of notional closed to be liquidated
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidateLiquidityPositions(
        Info storage account,
        uint16 liquidationFeeFraction,
        mapping(uint32 => address) storage vTokenAddresses,
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
            constants
        );
        if (accountMarketValue < totalRequiredMargin) {
            revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
        }
        // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, constants);

        int256 liquidationFeeHalf = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
        (keeperFee, insuranceFundFee) = computeLiquidationFees(accountMarketValue, fixFee, liquidationFeeHalf);

        account.chargeFee(uint256(keeperFee + insuranceFundFee), constants);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value > 0 ? value : -value;
    }

    function sign(int256 value) internal pure returns (int256) {
        return value > 0 ? int256(1) : int256(-1);
    }

    /// @notice liquidates all range positions in case the account is under water
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param liquidationParams parameters including liquidation fee fraction, target margin ratio, minimum liquidation amount and fix fee
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function liquidateTokenPosition(
        Info storage account,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256 keeperFee, int256 insuranceFundFee) {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            vTokenAddress,
            constants
        );
        int256 tokensToTrade;
        int256 accountMarketValue;

        {
            int256 totalRequiredMargin;

            (tokensToTrade, accountMarketValue, totalRequiredMargin) = account
                .tokenPositions
                .getTokenPositionToLiquidate(vTokenAddress, liquidationParams, vTokenAddresses, constants);

            if (accountMarketValue < totalRequiredMargin) {
                revert InvalidLiquidationAccountAbovewater(accountMarketValue, totalRequiredMargin);
            }

            if (sign(vTokenPosition.balance) * sign(tokensToTrade) > 0)
                revert InvalidTokenTradeAmount(vTokenPosition.balance, tokensToTrade);

            if (
                (abs(tokensToTrade) * int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants))) <
                liquidationParams.liquidationMinSizeBaseAmount.toInt256()
            ) {
                tokensToTrade = (-1 *
                    sign(vTokenPosition.balance) *
                    liquidationParams.liquidationMinSizeBaseAmount.toInt256());
            }
            if (abs(tokensToTrade) > abs(vTokenPosition.balance)) {
                tokensToTrade = -1 * vTokenPosition.balance;
            }
            // account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
            account.tokenPositions.swapTokenAmount(vTokenAddress, tokensToTrade, constants);

            int256 totalRequiredMarginFinal = account.tokenPositions.getRequiredMargin(
                false,
                vTokenAddresses,
                constants
            );

            if (totalRequiredMarginFinal < totalRequiredMargin)
                revert InvalidLiquidationWrongSide(totalRequiredMarginFinal, totalRequiredMargin);
        }
        accountMarketValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);

        int256 liquidationFeeHalf = (abs(tokensToTrade) *
            int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants))).mulDiv(
                liquidationParams.liquidationFeeFraction,
                1e5
            ) / 2;

        (keeperFee, insuranceFundFee) = computeLiquidationFees(
            accountMarketValue,
            liquidationParams.fixFee.toInt256(),
            liquidationFeeHalf
        );
        account.chargeFee(uint256(keeperFee + insuranceFundFee), constants);
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param constants platform constants
    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 limitOrderFee,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.removeLimitOrder(
            vTokenAddress,
            tickLower,
            tickUpper,
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapTick(constants),
            limitOrderFee,
            vTokenAddresses,
            VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
            constants
        );
    }

    /// @notice removes limit order based on the current price position (keeper call)
    /// @param account account to liquidate
    /// @param vTokenAddress address of token to swap
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param vTokenAddresses map of vTokenAddresses allowed on the platform
    /// @param wrapper poolwrapper for token
    /// @param constants platform constants
    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick,
        uint256 limitOrderFee,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
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
            account.tokenPositions.liquidityChange(
                vTokenAddress,
                position,
                -1 * int128(position.liquidity),
                wrapper,
                constants
            );
        } else {
            revert IneligibleLimitOrderRemoval();
        }

        account.chargeFee(limitOrderFee, constants);
    }
}
