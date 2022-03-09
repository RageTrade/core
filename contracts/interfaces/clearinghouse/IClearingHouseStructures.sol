//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IOracle } from '../IOracle.sol';
import { IVToken } from '../IVToken.sol';
import { IVPoolWrapper } from '../IVPoolWrapper.sol';

import { IClearingHouseEnums } from './IClearingHouseEnums.sol';

interface IClearingHouseStructures is IClearingHouseEnums {
    struct Collateral {
        IERC20 token;
        CollateralSettings settings; // mutable by governance
    }

    struct CollateralSettings {
        IOracle oracle;
        uint32 twapDuration;
        bool isAllowedForDeposit;
    }

    struct Pool {
        IVToken vToken;
        IUniswapV3Pool vPool;
        IVPoolWrapper vPoolWrapper;
        PoolSettings settings; // mutable by governance
    }

    struct PoolSettings {
        uint16 initialMarginRatio;
        uint16 maintainanceMarginRatio;
        uint32 twapDuration;
        bool isAllowedForTrade;
        bool isCrossMargined;
        IOracle oracle;
    }

    struct LiquidityChangeParams {
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
        uint160 sqrtPriceCurrent;
        uint16 slippageToleranceBps;
        bool closeTokenPosition;
        LimitOrderType limitOrderType;
    }

    /// @notice swaps params for specifying the swap params
    /// @param amount amount of tokens/base to swap
    /// @param sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
    /// @param isNotional specifies whether the amount represents token amount (false) or base amount(true)
    /// @param isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
    struct SwapParams {
        int256 amount;
        uint160 sqrtPriceLimit;
        bool isNotional;
        bool isPartialAllowed;
    }

    /// @notice parameters to be used for account balance update
    /// @param vQuoteIncrease specifies the increase in base balance
    /// @param vTokenIncrease specifies the increase in token balance
    /// @param traderPositionIncrease specifies the increase in trader position
    struct BalanceAdjustments {
        int256 vQuoteIncrease;
        int256 vTokenIncrease;
        int256 traderPositionIncrease;
    }

    /// @notice parameters to be used for liquidation
    /// @param liquidationFeeFraction specifies the percentage of notional value liquidated to be charged as liquidation fees (scaled by 1e5)
    /// @param tokenLiquidationPriceDeltaBps specifies the price delta from current perp price at which the liquidator should get the position (scaled by 1e4)
    /// @param insuranceFundFeeShare specifies the fee share for insurance fund out of the total liquidation fee (scaled by 1e4)
    /// @param maxRangeLiquidationFees specifies the the maximum range liquidation fees (in settlement token amount decimals)

    struct LiquidationParams {
        uint16 liquidationFeeFraction;
        uint16 tokenLiquidationPriceDeltaBps;
        uint16 insuranceFundFeeShareBps;
        uint128 maxRangeLiquidationFees;
    }

    struct DepositTokenView {
        IERC20 collateral;
        uint256 balance;
    }

    struct VTokenPositionView {
        IVToken vToken;
        int256 balance; // vTokenLong - vTokenShort
        int256 netTraderPosition;
        int256 sumAX128Ckpt;
        LiquidityPositionView[] liquidityPositions;
    }

    struct LiquidityPositionView {
        LimitOrderType limitOrderType;
        // the tick range of the position;
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        int256 vTokenAmountIn;
        // funding payment checkpoints
        int256 sumALastX128;
        int256 sumBInsideLastX128;
        int256 sumFpInsideLastX128;
        // fee growth inside
        uint256 sumFeeInsideLastX128;
    }

    struct MulticallOperation {
        MulticallOperationType operationType;
        bytes data;
    }

    struct SwapValues {
        int256 amountSpecified;
        int256 vTokenIn;
        int256 vQuoteIn;
        uint256 liquidityFees;
        uint256 protocolFees;
    }
}
