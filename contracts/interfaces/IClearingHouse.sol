//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IGovernable } from './IGovernable.sol';
import { IInsuranceFund } from './IInsuranceFund.sol';
import { IOracle } from './IOracle.sol';

import { IOracle } from './IOracle.sol';

import { IVBase } from './IVBase.sol';
import { IVPoolWrapper } from './IVPoolWrapper.sol';
import { IVToken } from './IVToken.sol';
import { Account } from '../libraries/Account.sol';
import { CTokenLib } from '../libraries/CTokenLib.sol';

interface IClearingHouse is IGovernable {
    struct Collateral {
        IERC20 token;
        CollateralSettings settings;
    }

    struct CollateralSettings {
        IOracle oracle;
        uint32 twapDuration;
        bool supported;
    }

    struct RageTradePool {
        IUniswapV3Pool vPool;
        IVPoolWrapper vPoolWrapper;
        RageTradePoolSettings settings;
    }

    struct RageTradePoolSettings {
        uint16 initialMarginRatio;
        uint16 maintainanceMarginRatio;
        uint32 twapDuration;
        bool supported;
        bool isCrossMargined;
        IOracle oracle;
    }

    enum LimitOrderType {
        NONE,
        LOWER_LIMIT,
        UPPER_LIMIT
    }

    enum MulticallOperationType {
        ADD_MARGIN,
        REMOVE_MARGIN,
        UPDATE_PROFIT,
        SWAP_TOKEN,
        UPDATE_RANGE_ORDER,
        REMOVE_LIMIT_ORDER,
        LIQUIDATE_LIQUIDITY_POSITIONS,
        LIQUIDATE_TOKEN_POSITION
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

    /// @notice parameters to be used for liquidation
    /// @param liquidationFeeFraction specifies the percentage of notional value liquidated to be charged as liquidation fees (scaled by 1e5)
    /// @param tokenLiquidationPriceDeltaBps specifies the price delta from current perp price at which the liquidator should get the position (scaled by 1e4)
    /// @param insuranceFundFeeShare specifies the fee share for insurance fund out of the total liquidation fee (scaled by 1e4)
    struct LiquidationParams {
        uint16 liquidationFeeFraction;
        uint16 tokenLiquidationPriceDeltaBps;
        uint16 insuranceFundFeeShareBps;
    }

    struct DepositTokenView {
        address cTokenAddress;
        uint256 balance;
    }

    struct VTokenPositionView {
        address vTokenAddress;
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
        int256 vBaseIn;
        uint256 liquidityFees;
        uint256 protocolFees;
    }

    /// @notice new rage trade pool supported
    /// @param vToken address of vToken
    event NewVTokenSupported(IVToken vToken);

    /// @notice new collateral supported as margin
    /// @param cTokenInfo collateral token info
    event CollateralSettingsUpdated(IERC20 cToken, CollateralSettings cTokenInfo);

    /// @notice maintainance margin ratio of a pool changed
    /// @param vToken address of vToken
    /// @param settings new settings
    event RageTradePoolSettingsUpdated(IVToken vToken, RageTradePoolSettings settings);

    /// @notice protocol settings changed
    /// @param liquidationParams liquidation params
    /// @param removeLimitOrderFee fee for remove limit order
    /// @param minimumOrderNotional minimum order notional
    /// @param minRequiredMargin minimum required margin
    event ProtocolSettingsUpdated(
        LiquidationParams liquidationParams,
        uint256 removeLimitOrderFee,
        uint256 minimumOrderNotional,
        uint256 minRequiredMargin
    );

    /// @notice error to denote invalid account access
    /// @param senderAddress address of msg sender
    error AccessDenied(address senderAddress);

    /// @notice error to denote usage of unsupported token
    /// @param vToken address of token
    error UnsupportedVToken(IVToken vToken);

    /// @notice error to denote usage of unsupported token
    /// @param cTokenAddress address of token
    error UnsupportedCToken(address cTokenAddress);

    /// @notice error to denote low notional value of txn
    /// @param notionalValue notional value of txn
    error LowNotionalValue(uint256 notionalValue);

    /// @notice error to denote incorrect address is supplied while updating collateral settings
    /// @param incorrectAddress incorrect address of collateral token
    /// @param correctAddress correct address of collateral token
    error IncorrectCollateralAddress(address incorrectAddress, address correctAddress);

    /// @notice error to denote invalid address supplied as a collateral token
    /// @param invalidAddress invalid address of collateral token
    error InvalidCollateralAddress(address invalidAddress);

    /// @notice error to denote invalid token liquidation (fraction to liquidate> 1)
    error InvalidTokenLiquidationParameters();

    /// @notice this is errored when the enum (uint8) value is out of bounds
    /// @param multicallOperationType is the value that is out of bounds
    error InvalidMulticallOperationType(IClearingHouse.MulticallOperationType multicallOperationType);

    /// @notice error to denote usage of unitialized token
    /// @param vTokenTruncatedAddress unitialized truncated address supplied
    error UninitializedToken(uint32 vTokenTruncatedAddress);

    /// @notice error to denote slippage of txn beyond set threshold
    error SlippageBeyondTolerance();

    /// @notice error to denote that keeper fee is negative or zero
    error KeeperFeeNotPositive(int256 keeperFee);

    /// @notice initializes clearing house contract
    /// @param rageTradeFactoryAddress rage trade factory address
    /// @param defaultCollateralToken address of default collateral token
    /// @param defaultCollateralTokenOracle address of default collateral token oracle
    /// @param insuranceFund address of insurance fund
    /// @param vBase address of vBase
    /// @param nativeOracle address of native oracle
    function __ClearingHouse_init(
        address rageTradeFactoryAddress,
        IERC20 defaultCollateralToken,
        IOracle defaultCollateralTokenOracle,
        IInsuranceFund insuranceFund,
        IVBase vBase,
        IOracle nativeOracle
    ) external;

    /// @notice updates the collataral settings
    /// @param cToken collateral token
    /// @param collateralSettings settings
    function updateCollateralSettings(IERC20 cToken, CollateralSettings memory collateralSettings) external;

    /// @notice updates the rage trade pool settings
    /// @param vToken address of vToken
    /// @param newSettings updated rage trade pool settings
    function updatePoolSettings(IVToken vToken, RageTradePoolSettings calldata newSettings) external;

    /// @notice updates the protocol settings
    /// @param liquidationParams liquidation params
    /// @param removeLimitOrderFee fee for remove limit order
    /// @param minimumOrderNotional minimum order notional
    /// @param minRequiredMargin minimum required margin
    function updateProtocolSettings(
        LiquidationParams calldata liquidationParams,
        uint256 removeLimitOrderFee,
        uint256 minimumOrderNotional,
        uint256 minRequiredMargin
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

    /// @notice creates a new account and deposits 'amount' of token associated with 'vTokenTruncatedAddress'
    /// @param vTokenTruncatedAddress truncated address of token to deposit
    /// @param amount amount of token to deposit
    /// @return newAccountId - serial number of the new account created
    function createAccountAndAddMargin(uint32 vTokenTruncatedAddress, uint256 amount)
        external
        returns (uint256 newAccountId);

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
    function updateProfit(uint256 accountNo, int256 amount) external;

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
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external;

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountNo account number
    function liquidateLiquidityPositions(uint256 accountNo) external;

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param liquidatorAccountNo liquidator account number
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidationBps fraction of the token position to be transferred in BPS
    /// @return liquidatorBalanceAdjustments - balance changes in liquidator base and token balance and net token position
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments);

    /// @notice keeper call to remove a limit order
    /// @dev checks the position of current price relative to limit order and checks limitOrderType
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param tickLower liquidity change parameters
    /// @param tickUpper liquidity change parameters
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return keeperFee : amount of fees paid to caller
    function removeLimitOrderWithGasClaim(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) external returns (uint256 keeperFee);

    /// @notice keeper call for liquidation of range position
    /// @dev removes all the active range positions and gives liquidator a percent of notional amount closed + fixedFee
    /// @param accountNo account number
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return keeperFee : amount of fees paid to caller
    function liquidateLiquidityPositionsWithGasClaim(uint256 accountNo, uint256 gasComputationUnitsClaim)
        external
        returns (int256 keeperFee);

    /// @notice keeper call for liquidation of token position
    /// @dev transfers the fraction of token position at a discount to current price to liquidators account and gives liquidator some fixedFee
    /// @param liquidatorAccountNo liquidator account number
    /// @param accountNo account number
    /// @param vTokenTruncatedAddress truncated address of token to withdraw
    /// @param liquidationBps fraction of the token position to be transferred in BPS
    /// @param gasComputationUnitsClaim estimated computation gas units, if more than actual, tx will revert
    /// @return liquidatorBalanceAdjustments - balance changes in liquidator base and token balance and net token position
    function liquidateTokenPositionWithGasClaim(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments);

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool);

    function registerPool(address full, RageTradePool calldata rageTradePool) external;

    function getTwapSqrtPricesForSetDuration(IVToken vToken)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128);

    /**
        Account.ProtocolInfo VIEW
     */
    function protocolInfo()
        external
        view
        returns (
            IVBase vBase,
            LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        );

    function pools(IVToken vToken) external view returns (RageTradePool memory);

    function cTokens(uint32 cTokenId) external view returns (Collateral memory);

    function vTokens(uint32 vTokenAddressTruncated) external view returns (IVToken);

    /**
        Account.UserInfo VIEW
     */

    function getAccountView(uint256 accountNo)
        external
        view
        returns (
            address owner,
            int256 vBaseBalance,
            DepositTokenView[] memory tokenDeposits,
            VTokenPositionView[] memory tokenPositions
        );

    function getAccountMarketValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin);

    function getAccountNetProfit(uint256 accountNo) external view returns (int256 accountNetProfit);
}
