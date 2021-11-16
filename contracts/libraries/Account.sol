//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VBASE_ADDRESS, RBASE_ADDRESS } from '../Constants.sol';

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

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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
        uint256 amount
    ) internal {
        // collect
        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transferFrom(msg.sender, address(this), amount);
        // vBASE should be an immutable constant
        account.tokenDeposits.increaseBalance(vTokenAddress, amount);
    }

    function removeMargin(
        Info storage account,
        address vTokenAddress,
        uint256 amount,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal {
        account.tokenDeposits.decreaseBalance(vTokenAddress, amount);

        require(account.checkIfMarginAvailable(true, vTokenAddresses), 'Cannot Withdraw');

        // process real token withdrawal
        IERC20(VTokenAddress.wrap(vTokenAddress).realToken()).transfer(msg.sender, amount);
    }

    function removeProfit(
        Info storage account,
        uint256 amount,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(VBASE_ADDRESS);
        vTokenPosition.balance -= int256(amount);

        require(account.checkIfMarginAvailable(true, vTokenAddresses), 'Cannot Withdraw - Not enough margin');
        require(account.checkIfProfitAvailable(vTokenAddresses), 'Cannot Withdraw - Not enough profit');

        IERC20(RBASE_ADDRESS).transfer(msg.sender, amount);
    }

    function getAccountValueAndRequiredMargin(
        Info storage account,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal view returns (int256, int256) {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account
            .tokenPositions
            .getAllTokenPositionValueAndMargin(isInitialMargin, vTokenAddresses);
        accountMarketValue += account.tokenDeposits.getAllDepositAccountMarketValue(vTokenAddresses);
        return (accountMarketValue, totalRequiredMargin);
    }

    function checkIfMarginAvailable(
        Info storage account,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal view returns (bool) {
        (int256 accountMarketValue, int256 totalRequiredMargin) = account.getAccountValueAndRequiredMargin(
            isInitialMargin,
            vTokenAddresses
        );
        return accountMarketValue >= totalRequiredMargin;
    }

    function checkIfProfitAvailable(Info storage account, mapping(uint32 => address) storage vTokenAddresses)
        internal
        view
        returns (bool)
    {
        (int256 totalPositionValue, int256 totalRequiredMargin) = account
            .tokenPositions
            .getAllTokenPositionValueAndMargin(false, vTokenAddresses);
        return totalPositionValue > 0;
    }

    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        account.tokenPositions.swapTokenAmount(vTokenAddress, vTokenAmount, wrapper);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    //vTokenNotional > 0 => long in token
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. and send to the pool
        account.tokenPositions.swapTokenNotional(vTokenAddress, vTokenNotional, wrapper);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    //vTokenAmount > 0 => long in token
    function swapTokenAmount(
        Info storage account,
        address vTokenAddress,
        int256 vTokenAmount,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. an  d send to the pool
        account.tokenPositions.swapTokenAmount(vTokenAddress, vTokenAmount);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    //vTokenNotional > 0 => long in token
    function swapTokenNotional(
        Info storage account,
        address vTokenAddress,
        int256 vTokenNotional,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal {
        // account fp bill
        account.tokenPositions.realizeFundingPayment(vTokenAddresses); // also updates checkpoints

        // make a swap. vBaseIn and vTokenAmountOut (in and out wrt uniswap).
        // mints erc20 tokens in callback. and send to the pool
        account.tokenPositions.swapTokenNotional(vTokenAddress, vTokenNotional);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    function liquidityChange(
        Info storage account,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper
    ) internal {
        account.tokenPositions.realizeFundingPayment(vTokenAddresses);

        // mint/burn tokens + fee + funding payment
        account.tokenPositions.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    function liquidityChange(
        Info storage account,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal {
        account.tokenPositions.realizeFundingPayment(vTokenAddresses);
        // mint/burn tokens + fee + funding payment

        account.tokenPositions.liquidityChange(vTokenAddress, liquidityChangeParams);

        // after all the stuff, account should be above water
        require(account.checkIfMarginAvailable(true, vTokenAddresses));
    }

    //Fee Fraction * e6 is input
    //Fee can be positive and negative (in case of negative fee insurance fund is to take care of the whole thing
    function liquidateLiquidityPositions(
        Info storage account,
        uint16 liquidationFeeFraction,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper
    ) internal returns (int256, int256) {
        //check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 notionalAmountClosed;
        int256 fixFee;

        (accountMarketValue, totalRequiredMargin) = account.getAccountValueAndRequiredMargin(false, vTokenAddresses);
        // require(accountMarketValue < totalRequiredMargin, "Account not underwater");

        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses, wrapper);

        if (accountMarketValue < 0) {
            return (fixFee, -1 * (abs(accountMarketValue) + fixFee));
        } else {
            int256 fee = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
            return (fee + fixFee, fee);
        }
    }

    //Fee Fraction * e6 is input
    //Fee can be positive and negative (in case of negative fee insurance fund is to take care of the whole thing
    function liquidateLiquidityPositions(
        Info storage account,
        uint16 liquidationFeeFraction,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal returns (int256, int256) {
        //check basis maintanace margin
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 notionalAmountClosed;
        int256 fixFee;

        (accountMarketValue, totalRequiredMargin) = account.getAccountValueAndRequiredMargin(false, vTokenAddresses);
        require(accountMarketValue < totalRequiredMargin, 'Account not underwater');

        notionalAmountClosed = account.tokenPositions.liquidateLiquidityPositions(vTokenAddresses);

        if (accountMarketValue < 0) {
            return (fixFee, -1 * (abs(accountMarketValue) + fixFee));
        } else {
            int256 fee = (notionalAmountClosed * int256(int16(liquidationFeeFraction))) / 2;
            return (fee + fixFee, fee);
        }
        // if (accountMarketValue<0) {
        //     insuranceFund.request(-accountMarketValue);
        // } else {
        //     insuranceFund.transfer(fee/2);
        //     IERC20(RBASE_ADDRESS).transfer(msg.sender(),fee/2);
        // }
    }

    function abs(int256 value) internal pure returns (int256) {
        if (value < 0) return value * -1;
        else return value;
    }

    function sign(int256 value) internal pure returns (int256) {
        if (value < 0) return -1;
        else return 1;
    }

    function liquidateTokenPosition(
        Info storage account,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal returns (int256, int256) {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(vTokenAddress);
        int256 tokensToTrade;
        int256 accountMarketValue;

        {
            int256 totalRequiredMargin;
            int256 totalRequiredMarginFinal;

            (tokensToTrade, accountMarketValue, totalRequiredMargin) = account
                .tokenPositions
                .getTokenPositionToLiquidate(vTokenAddress, liquidationParams, vTokenAddresses);

            require(accountMarketValue < totalRequiredMargin, 'Account not underwater');

            if (vTokenPosition.balance < 0) {
                require(tokensToTrade > 0, 'Invalid token amount to trade');
            } else {
                require(tokensToTrade < 0, 'Invalid token amount to trade');
            }

            int256 absTokensToTrade = abs(tokensToTrade);

            if (
                (absTokensToTrade * int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice())) <
                liquidationParams.liquidationMinSizeBaseAmount.toInt256()
            ) {
                tokensToTrade = (-1 *
                    sign(vTokenPosition.balance) *
                    liquidationParams.liquidationMinSizeBaseAmount.toInt256());
            }
            if (absTokensToTrade > abs(vTokenPosition.balance)) {
                tokensToTrade = -1 * vTokenPosition.balance;
            }

            account.tokenPositions.swapTokenAmount(vTokenAddress, tokensToTrade);

            totalRequiredMarginFinal = account.tokenPositions.getRequiredMargin(false, vTokenAddresses);

            require(totalRequiredMarginFinal < totalRequiredMargin, 'Invalid position liquidation (Wrong Side)');
        }
        accountMarketValue = account.tokenPositions.getAccountMarketValue(vTokenAddresses);

        if (accountMarketValue < 0) {
            return (
                liquidationParams.fixFee.toInt256(),
                -1 * (abs(accountMarketValue) + liquidationParams.fixFee.toInt256())
            );
        } else {
            int256 fee = (abs(tokensToTrade) * int256(VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice())).mulDiv(
                liquidationParams.liquidationFeeFraction,
                1e5
            ) / 2;
            return (fee + liquidationParams.fixFee.toInt256(), fee);
        }
    }

    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        account.removeLimitOrder(
            vTokenAddress,
            tickLower,
            tickUpper,
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapTick()
        );
    }

    function removeLimitOrder(
        Info storage account,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick
    ) internal {
        VTokenPosition.Position storage vTokenPosition = account.tokenPositions.getTokenPosition(vTokenAddress);

        LiquidityPosition.Info storage position = vTokenPosition.liquidityPositions.getLiquidityPosition(
            tickLower,
            tickUpper
        );

        if (
            (currentTick >= tickUpper && position.limitOrderType == LimitOrderType.UPPER_LIMIT) ||
            (currentTick <= tickLower && position.limitOrderType == LimitOrderType.LOWER_LIMIT)
        ) {
            account.tokenPositions.liquidityChange(vTokenAddress, position, -1 * int128(position.liquidity));
        }
    }
}
