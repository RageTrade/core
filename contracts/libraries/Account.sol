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
import { Constants } from '../Constants.sol';

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

    // @dev some functions in token position and liquidity position want to
    //  change user's balances. pointer to this memory struct is passed and
    //  the inner methods update values. after the function exec these can
    //  be applied to user's virtual balance.
    //  example: see liquidityChange in LiquidityPosition
    struct BalanceAdjustments {
        int256 vBaseIncrease;
        int256 vTokenIncrease;
        int256 traderPositionIncrease;
    }

    struct Info {
        address owner;
        uint64 fpBilledPrevious;
        VTokenPositionSet.Set tokenPositions;
        DepositTokenSet.Info tokenDeposits;
    }

    function isInitialized(Info storage account) internal view returns (bool) {
        return account.owner != address(0);
    }

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

    function getAccountValueAndRequiredMargin(
        Info storage account,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256, int256) {
        // (int256 accountMarketValue, int256 totalRequiredMargin) = account
        //     .tokenPositions
        //     .getAllTokenPositionValueAndMargin(isInitialMargin, vTokenAddresses, constants);
        int256 accountMarketValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        int256 totalRequiredMargin = account.tokenPositions.getRequiredMargin(
            isInitialMargin,
            vTokenAddresses,
            constants
        );
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(vTokenAddresses, constants);
        return (accountMarketValue, totalRequiredMargin);
    }

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

    function checkIfProfitAvailable(
        Info storage account,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view {
        int256 totalPositionValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses, constants);
        if (totalPositionValue < 0) revert InvalidTransactionNotEnoughProfit(totalPositionValue);
    }

    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        account.tokenPositions.swapTokenAmount(vTokenAddress, vTokenAmount, wrapper, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

    //vTokenNotional > 0 => long in token
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. and send to the pool
        account.tokenPositions.swapTokenNotional(vTokenAddress, vTokenNotional, wrapper, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

    //vTokenAmount > 0 => long in token
    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.swapTokenAmount(
            vTokenAddress,
            vTokenAmount,
            vTokenAddresses,
            VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
            constants
        );
    }

    //vTokenNotional > 0 => long in token
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.swapTokenNotional(
            vTokenAddress,
            vTokenNotional,
            vTokenAddresses,
            VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
            constants
        );
    }

    function liquidityChange(
        Info storage account,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants);

        // mint/burn tokens + fee + funding payment
        account.tokenPositions.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper, constants);

        // after all the stuff, account should be above water
        account.checkIfMarginAvailable(true, vTokenAddresses, constants);
    }

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

    function computeLiquidationFees(
        int256 accountMarketValue,
        int256 fixFee,
        int256 liquidationFeeHalf
    ) internal pure returns (int256 keeperFees, int256 insuranceFundFees) {
        if (accountMarketValue - fixFee - 2 * liquidationFeeHalf < 0) {
            keeperFees = fixFee;
            insuranceFundFees = accountMarketValue - fixFee;
        } else {
            keeperFees = liquidationFeeHalf + fixFee;
            insuranceFundFees = liquidationFeeHalf;
        }
    }

    //Fee Fraction * e6 is input
    //Fee can be positive and negative (in case of negative fee insurance fund is to take care of the whole thing
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
        account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, wrapper, constants);

        int256 liquidationFeeHalf = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
        return computeLiquidationFees(accountMarketValue, fixFee, liquidationFeeHalf);
    }

    //Fee Fraction * e6 is input
    //Fee can be positive and negative (in case of negative fee insurance fund is to take care of the whole thing
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
        account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, constants);

        int256 liquidationFeeHalf = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
        return computeLiquidationFees(accountMarketValue, fixFee, liquidationFeeHalf);
    }

    function abs(int256 value) internal pure returns (int256) {
        return value > 0 ? value : -value;
    }

    function sign(int256 value) internal pure returns (int256) {
        return value > 0 ? int256(1) : int256(-1);
    }

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
                (abs(tokensToTrade) * int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice(constants))) <
                liquidationParams.liquidationMinSizeBaseAmount.toInt256()
            ) {
                tokensToTrade = (-1 *
                    sign(vTokenPosition.balance) *
                    liquidationParams.liquidationMinSizeBaseAmount.toInt256());
            }
            if (abs(tokensToTrade) > abs(vTokenPosition.balance)) {
                tokensToTrade = -1 * vTokenPosition.balance;
            }
            account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
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
            int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice(constants))).mulDiv(
                liquidationParams.liquidationFeeFraction,
                1e5
            ) / 2;

        return computeLiquidationFees(accountMarketValue, liquidationParams.fixFee.toInt256(), liquidationFeeHalf);
    }

    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        account.removeLimitOrder(
            vTokenAddress,
            tickLower,
            tickUpper,
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapTick(constants),
            vTokenAddresses,
            VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
            constants
        );
    }

    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(
            vTokenAddress,
            constants
        );

        LiquidityPosition.Info storage position = vTokenPosition.liquidityPositions.getLiquidityPosition(
            tickLower,
            tickUpper
        );

        if (
            (currentTick >= tickUpper && position.limitOrderType == LimitOrderType.UPPER_LIMIT) ||
            (currentTick <= tickLower && position.limitOrderType == LimitOrderType.LOWER_LIMIT)
        ) {
            account.tokenPositions.realizeFundingPayment(vTokenAddresses, constants); // also updates checkpoints
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
    }
}
