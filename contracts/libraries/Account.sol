//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

library Account {
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
}
