//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IGovernable } from './IGovernable.sol';
import { IInsuranceFund } from './IInsuranceFund.sol';
import { IOracle } from './IOracle.sol';
import { IVBase } from './IVBase.sol';
import { IVPoolWrapper } from './IVPoolWrapper.sol';
import { IVToken } from './IVToken.sol';

// TODO move these to interface
import { Account } from '../libraries/Account.sol';

interface IClearingHouse is IGovernable {
    struct RageTradePool {
        IUniswapV3Pool vPool;
        IVPoolWrapper vPoolWrapper;
        RageTradePoolSettings settings;
    }

    struct RageTradePoolSettings {
        uint16 initialMarginRatio;
        uint16 maintainanceMarginRatio;
        uint32 twapDuration;
        bool whitelisted;
        IOracle oracle;
    }

    enum LimitOrderType {
        NONE,
        LOWER_LIMIT,
        UPPER_LIMIT
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
    /// @param vBaseIncrease specifies the increase in base balance
    /// @param vTokenIncrease specifies the increase in token balance
    /// @param traderPositionIncrease specifies the increase in trader position
    struct BalanceAdjustments {
        int256 vBaseIncrease;
        int256 vTokenIncrease;
        int256 traderPositionIncrease;
    }

    /// @notice error to denote invalid account access
    /// @param senderAddress address of msg sender
    error AccessDenied(address senderAddress);

    /// @notice error to denote usage of unsupported token
    /// @param vToken address of token
    error UnsupportedVToken(IVToken vToken);

    /// @notice error to denote usage of unsupported token
    /// @param rTokenAddress address of token
    error UnsupportedRToken(address rTokenAddress);

    /// @notice error to denote low notional value of txn
    /// @param notionalValue notional value of txn
    error LowNotionalValue(uint256 notionalValue);

    /// @notice error to denote invalid token liquidation (fraction to liquidate> 1)
    error InvalidTokenLiquidationParameters();

    /// @notice error to denote usage of unitialized token
    /// @param vTokenTruncatedAddress unitialized truncated address supplied
    error UninitializedToken(uint32 vTokenTruncatedAddress);

    /// @notice error to denote slippage of txn beyond set threshold
    error SlippageBeyondTolerance();

    function __ClearingHouse_init(
        address _rageTradeFactoryAddress,
        IERC20 _rBase,
        IInsuranceFund _insuranceFund,
        IVBase _vBase,
        IOracle _nativeOracle
    ) external;

    /// @notice creates a new account and adds it to the accounts map
    /// @return newAccountId - serial number of the new account created
    function createAccount() external returns (uint256 newAccountId);

    /// @notice withdraws protocol fees collected in the supplied wrappers to team multisig
    /// @param wrapperAddresses list of wrapper addresses to collect fees from
    function withdrawProtocolFee(address[] calldata wrapperAddresses) external;

    /// @notice deposits 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to deposit
    /// @param amount amount of token to deposit
    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    /// @notice withdraws 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param amount amount of token to withdraw
    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external;

    /// @notice withdraws 'amount' of base token from the profit made
    /// @param accountNo account number
    /// @param amount amount of token to withdraw
    function removeProfit(uint256 accountNo, uint256 amount) external;

    /// @notice swaps token associated with 'vTokenTruncatedAddress' by 'amount' (Long if amount>0 else Short)
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param swapParams swap parameters
    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    /// @notice updates range order of token associated with 'vTokenTruncatedAddress' by 'liquidityDelta' (Adds if amount>0 else Removes)
    /// @notice also can be used to update limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidityChangeParams liquidity change parameters
    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external returns (int256 vTokenAmountOut, int256 vBaseAmountOut);

    /// @notice keeper call to remove a limit order
    /// @dev checks the position of current price relative to limit order and checks limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param tickLower liquidity change parameters
    /// @param tickUpper liquidity change parameters
    // @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 keeperFee);

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountNo account number
    // @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    function liquidateLiquidityPositions(uint256 accountNo) external returns (int256 keeperFee);

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param liquidatorAccountNo liquidator account number
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidationBps fraction of the token position to be transferred in BPS
    // @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return liquidatorBalanceAdjustments - balance changes in liquidator base and token balance and net token position
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments);

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool);

    function registerPool(address full, RageTradePool calldata rageTradePool) external;

    function getTwapSqrtPricesForSetDuration(IVToken vToken)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128);
}
