// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IExtsload } from '../interfaces/IExtsload.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { WordHelper } from '../libraries/WordHelper.sol';
import { Uint48Lib } from '../libraries/Uint48.sol';

import 'hardhat/console.sol';

library ClearingHouseExtsload {
    // Terminology:
    // SLOT is a storage location value which can be sloaded, typed in bytes32.
    // OFFSET is an slot offset value which should not be sloaded, henced typed in uint256.

    using WordHelper for bytes32;
    using WordHelper for WordHelper.Word;

    bytes32 constant ZERO = bytes32(uint256(0));

    /**
     * PROTOCOL
     */

    bytes32 constant PROTOCOL_SLOT = bytes32(uint256(100));
    uint256 constant PROTOCOL_POOLS_MAPPING_OFFSET = 0;
    uint256 constant PROTOCOL_COLLATERALS_MAPPING_OFFSET = 1;
    uint256 constant PROTOCOL_SETTLEMENT_TOKEN_OFFSET = 2;
    uint256 constant PROTOCOL_VQUOTE_OFFSET = 3;
    uint256 constant PROTOCOL_LIQUIDATION_PARAMS_STRUCT_OFFSET = 4;
    uint256 constant PROTOCOL_MINIMUM_REQUIRED_MARGIN_OFFSET = 5;
    uint256 constant PROTOCOL_REMOVE_LIMIT_ORDER_FEE_OFFSET = 6;
    uint256 constant PROTOCOL_MINIMUM_ORDER_NOTIONAL_OFFSET = 7;

    function _decodeLiquidationParamsSlot(bytes32 data)
        internal
        pure
        returns (IClearingHouse.LiquidationParams memory liquidationParams)
    {
        WordHelper.Word memory result = data.copyToMemory();
        liquidationParams.rangeLiquidationFeeFraction = result.popUint16();
        liquidationParams.tokenLiquidationFeeFraction = result.popUint16();
        liquidationParams.closeFactorMMThresholdBps = result.popUint16();
        liquidationParams.partialLiquidationCloseFactorBps = result.popUint16();
        liquidationParams.insuranceFundFeeShareBps = result.popUint16();
        liquidationParams.liquidationSlippageSqrtToleranceBps = result.popUint16();
        liquidationParams.maxRangeLiquidationFees = result.popUint64();
        liquidationParams.minNotionalLiquidatable = result.popUint64();
    }

    /// @notice Gets the protocol info, global protocol settings
    /// @return settlementToken the token in which profit is settled
    /// @return vQuote the vQuote token contract
    /// @return liquidationParams the liquidation parameters
    /// @return minRequiredMargin minimum required margin an account has to keep with non-zero netPosition
    /// @return removeLimitOrderFee the fee charged for using removeLimitOrder service
    /// @return minimumOrderNotional the minimum order notional
    function getProtocolInfo(IClearingHouse clearingHouse)
        internal
        view
        returns (
            IERC20 settlementToken,
            IVQuote vQuote,
            IClearingHouse.LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        bytes32[] memory arr = new bytes32[](6);
        arr[0] = PROTOCOL_SLOT.offset(PROTOCOL_SETTLEMENT_TOKEN_OFFSET);
        arr[1] = PROTOCOL_SLOT.offset(PROTOCOL_VQUOTE_OFFSET);
        arr[2] = PROTOCOL_SLOT.offset(PROTOCOL_LIQUIDATION_PARAMS_STRUCT_OFFSET);
        arr[3] = PROTOCOL_SLOT.offset(PROTOCOL_MINIMUM_REQUIRED_MARGIN_OFFSET);
        arr[4] = PROTOCOL_SLOT.offset(PROTOCOL_REMOVE_LIMIT_ORDER_FEE_OFFSET);
        arr[5] = PROTOCOL_SLOT.offset(PROTOCOL_MINIMUM_ORDER_NOTIONAL_OFFSET);
        arr = clearingHouse.extsload(arr);
        settlementToken = IERC20(arr[0].toAddress());
        vQuote = IVQuote(arr[1].toAddress());
        liquidationParams = _decodeLiquidationParamsSlot(arr[2]);
        minRequiredMargin = arr[3].toUint256();
        removeLimitOrderFee = arr[4].toUint256();
        minimumOrderNotional = arr[5].toUint256();
    }

    /**
     * PROTOCOL POOLS MAPPING
     */

    uint256 constant POOL_VTOKEN_OFFSET = 0;
    uint256 constant POOL_VPOOL_OFFSET = 1;
    uint256 constant POOL_VPOOLWRAPPER_OFFSET = 2;
    uint256 constant POOL_SETTINGS_STRUCT_OFFSET = 3;

    function poolStructSlot(uint32 poolId) internal pure returns (bytes32) {
        return
            WordHelper.keccak256Two({
                mappingSlot: PROTOCOL_SLOT.offset(PROTOCOL_POOLS_MAPPING_OFFSET),
                paddedKey: WordHelper.fromUint(poolId)
            });
    }

    function _decodePoolSettingsSlot(bytes32 data) internal pure returns (IClearingHouse.PoolSettings memory settings) {
        WordHelper.Word memory result = data.copyToMemory();
        settings.initialMarginRatioBps = result.popUint16();
        settings.maintainanceMarginRatioBps = result.popUint16();
        settings.maxVirtualPriceDeviationRatioBps = result.popUint16();
        settings.twapDuration = result.popUint32();
        settings.isAllowedForTrade = result.popBool();
        settings.isCrossMargined = result.popBool();
        settings.oracle = IOracle(result.popAddress());
    }

    /// @notice Gets the info about a supported pool in the protocol
    /// @param poolId the id of the pool
    /// @return pool the Pool struct
    function getPoolInfo(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IClearingHouse.Pool memory pool)
    {
        bytes32 POOL_SLOT = poolStructSlot(poolId);
        bytes32[] memory arr = new bytes32[](4);
        arr[0] = POOL_SLOT; // POOL_VTOKEN_OFFSET
        arr[1] = POOL_SLOT.offset(POOL_VPOOL_OFFSET);
        arr[2] = POOL_SLOT.offset(POOL_VPOOLWRAPPER_OFFSET);
        arr[3] = POOL_SLOT.offset(POOL_SETTINGS_STRUCT_OFFSET);
        arr = clearingHouse.extsload(arr);
        pool.vToken = IVToken(arr[0].toAddress());
        pool.vPool = IUniswapV3Pool(arr[1].toAddress());
        pool.vPoolWrapper = IVPoolWrapper(arr[2].toAddress());
        pool.settings = _decodePoolSettingsSlot(arr[3]);
    }

    function getVPool(IClearingHouse clearingHouse, uint32 poolId) internal view returns (IUniswapV3Pool vPool) {
        bytes32 result = clearingHouse.extsload(poolStructSlot(poolId).offset(POOL_VPOOL_OFFSET));
        assembly {
            vPool := result
        }
    }

    function getPoolSettings(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IClearingHouse.PoolSettings memory)
    {
        bytes32 SETTINGS_SLOT = poolStructSlot(poolId).offset(POOL_SETTINGS_STRUCT_OFFSET);
        return _decodePoolSettingsSlot(clearingHouse.extsload(SETTINGS_SLOT));
    }

    function getTwapDuration(IClearingHouse clearingHouse, uint32 poolId) internal view returns (uint32 twapDuration) {
        bytes32 result = clearingHouse.extsload(poolStructSlot(poolId).offset(POOL_SETTINGS_STRUCT_OFFSET));
        twapDuration = result.slice(0x30, 0x50).toUint32();
    }

    function getVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        internal
        view
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        bytes32[] memory arr = new bytes32[](2);

        bytes32 POOL_SLOT = poolStructSlot(poolId);
        arr[0] = POOL_SLOT.offset(POOL_VPOOL_OFFSET); // vPool
        arr[1] = POOL_SLOT.offset(POOL_SETTINGS_STRUCT_OFFSET); // settings
        arr = clearingHouse.extsload(arr);

        vPool = IUniswapV3Pool(arr[0].toAddress());
        twapDuration = arr[1].slice(0xB0, 0xD0).toUint32();
    }

    /// @notice Checks if a poolId is unused
    /// @param poolId the id of the pool
    /// @return true if the poolId is unused, false otherwise
    function isPoolIdAvailable(IClearingHouse clearingHouse, uint32 poolId) internal view returns (bool) {
        bytes32 VTOKEN_SLOT = poolStructSlot(poolId).offset(POOL_VTOKEN_OFFSET);
        bytes32 result = clearingHouse.extsload(VTOKEN_SLOT);
        return result == WordHelper.fromUint(0);
    }

    /**
     * PROTOCOL COLLATERALS MAPPING
     */

    uint256 constant COLLATERAL_TOKEN_OFFSET = 0;
    uint256 constant COLLATERAL_SETTINGS_OFFSET = 1;

    function collateralStructSlot(uint32 collateralId) internal pure returns (bytes32) {
        return
            WordHelper.keccak256Two({
                mappingSlot: PROTOCOL_SLOT.offset(PROTOCOL_COLLATERALS_MAPPING_OFFSET),
                paddedKey: WordHelper.fromUint(collateralId)
            });
    }

    function _decodeCollateralSettings(bytes32 data)
        internal
        pure
        returns (IClearingHouse.CollateralSettings memory settings)
    {
        WordHelper.Word memory result = data.copyToMemory();
        settings.oracle = IOracle(result.popAddress());
        settings.twapDuration = result.popUint32();
        settings.isAllowedForDeposit = result.popBool();
    }

    /// @notice Gets the info about a supported collateral in the protocol
    /// @param collateralId the id of the collateral
    /// @return collateral the Collateral struct
    function getCollateralInfo(IClearingHouse clearingHouse, uint32 collateralId)
        internal
        view
        returns (IClearingHouse.Collateral memory collateral)
    {
        bytes32[] memory arr = new bytes32[](2);
        bytes32 COLLATERAL_STRUCT_SLOT = collateralStructSlot(collateralId);
        arr[0] = COLLATERAL_STRUCT_SLOT; // COLLATERAL_TOKEN_OFFSET
        arr[1] = COLLATERAL_STRUCT_SLOT.offset(COLLATERAL_SETTINGS_OFFSET);
        arr = clearingHouse.extsload(arr);
        collateral.token = IVToken(arr[0].toAddress());
        collateral.settings = _decodeCollateralSettings(arr[1]);
    }

    /**
     * ACCOUNT MAPPING
     */
    bytes32 constant ACCOUNTS_MAPPING_SLOT = bytes32(uint256(209));
    uint256 constant ACCOUNT_ID_OWNER_OFFSET = 0;
    uint256 constant ACCOUNT_VTOKENPOSITIONS_ACTIVE_SET_OFFSET = 1;
    uint256 constant ACCOUNT_VTOKENPOSITIONS_MAPPING_OFFSET = 2;
    uint256 constant ACCOUNT_VQUOTE_BALANCE_OFFSET = 3;
    uint256 constant ACCOUNT_COLLATERAL_ACTIVE_SET_OFFSET = 104;
    uint256 constant ACCOUNT_COLLATERAL_MAPPING_OFFSET = 105;

    // VTOKEN POSITION STRUCT
    uint256 constant ACCOUNT_VTOKENPOSITION_BALANCE_OFFSET = 0;
    uint256 constant ACCOUNT_VTOKENPOSITION_NET_TRADER_POSITION_OFFSET = 1;
    uint256 constant ACCOUNT_VTOKENPOSITION_SUM_A_LAST_OFFSET = 2;
    uint256 constant ACCOUNT_VTOKENPOSITION_LIQUIDITY_ACTIVE_OFFSET = 3;
    uint256 constant ACCOUNT_VTOKENPOSITION_LIQUIDITY_MAPPING_OFFSET = 4;

    // LIQUIDITY POSITION STRUCT
    uint256 constant ACCOUNT_TP_LP_SLOT0_OFFSET = 0; // limit order type, tl, tu, liquidity
    uint256 constant ACCOUNT_TP_LP_VTOKEN_AMOUNTIN_OFFSET = 1;
    uint256 constant ACCOUNT_TP_LP_SUM_A_LAST_OFFSET = 2;
    uint256 constant ACCOUNT_TP_LP_SUM_B_LAST_OFFSET = 3;
    uint256 constant ACCOUNT_TP_LP_SUM_FP_LAST_OFFSET = 4;
    uint256 constant ACCOUNT_TP_LP_SUM_FEE_LAST_OFFSET = 5;

    function accountStructSlot(uint256 accountId) internal pure returns (bytes32) {
        return
            WordHelper.keccak256Two({ mappingSlot: ACCOUNTS_MAPPING_SLOT, paddedKey: WordHelper.fromUint(accountId) });
    }

    function accountCollateralStructSlot(bytes32 ACCOUNT_STRUCT_SLOT, uint32 collateralId)
        internal
        pure
        returns (bytes32)
    {
        return
            WordHelper.keccak256Two({
                mappingSlot: ACCOUNT_STRUCT_SLOT.offset(ACCOUNT_COLLATERAL_MAPPING_OFFSET),
                paddedKey: WordHelper.fromUint(collateralId)
            });
    }

    function accountVTokenPositionStructSlot(bytes32 ACCOUNT_STRUCT_SLOT, uint32 poolId)
        internal
        pure
        returns (bytes32)
    {
        return
            WordHelper.keccak256Two({
                mappingSlot: ACCOUNT_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITIONS_MAPPING_OFFSET),
                paddedKey: WordHelper.fromUint(poolId)
            });
    }

    function accountLiquidityPositionStructSlot(
        bytes32 ACCOUNT_VTOKENPOSITION_STRUCT_SLOT,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return
            WordHelper.keccak256Two({
                mappingSlot: ACCOUNT_VTOKENPOSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_LIQUIDITY_MAPPING_OFFSET),
                paddedKey: WordHelper.fromUint(Uint48Lib.concat(tickLower, tickUpper))
            });
    }

    function getAccountInfo(IClearingHouse clearingHouse, uint256 accountId)
        internal
        view
        returns (
            address owner,
            int256 vQuoteBalance,
            uint32[] memory activeCollateralIds,
            uint32[] memory activePoolIds
        )
    {
        bytes32[] memory arr = new bytes32[](4);
        bytes32 ACCOUNT_SLOT = accountStructSlot(accountId);
        arr[0] = ACCOUNT_SLOT; // ACCOUNT_ID_OWNER_OFFSET
        arr[1] = ACCOUNT_SLOT.offset(ACCOUNT_VQUOTE_BALANCE_OFFSET);
        arr[2] = ACCOUNT_SLOT.offset(ACCOUNT_COLLATERAL_ACTIVE_SET_OFFSET);
        arr[3] = ACCOUNT_SLOT.offset(ACCOUNT_VTOKENPOSITIONS_ACTIVE_SET_OFFSET);

        arr = clearingHouse.extsload(arr);

        owner = arr[0].slice(0, 160).toAddress();
        vQuoteBalance = arr[1].toInt256();
        activeCollateralIds = convertToUint32Array(arr[2]);
        activePoolIds = convertToUint32Array(arr[3]);
    }

    function getAccountCollateralInfo(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 collateralId
    ) internal view returns (IERC20 collateral, uint256 balance) {
        bytes32[] memory arr = new bytes32[](2);
        arr[0] = accountCollateralStructSlot(accountStructSlot(accountId), collateralId); // ACCOUNT_COLLATERAL_BALANCE_SLOT
        arr[1] = collateralStructSlot(collateralId); // COLLATERAL_TOKEN_ADDRESS_SLOT

        arr = clearingHouse.extsload(arr);

        balance = arr[0].toUint256();
        collateral = IERC20(arr[1].toAddress());
    }

    function getAccountCollateralBalance(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 collateralId
    ) internal view returns (uint256 balance) {
        bytes32 COLLATERAL_BALANCE_SLOT = accountCollateralStructSlot(accountStructSlot(accountId), collateralId);

        balance = clearingHouse.extsload(COLLATERAL_BALANCE_SLOT).toUint256();
    }

    function getAccountTokenPositionInfo(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 poolId
    )
        internal
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumALastX128
        )
    {
        bytes32 VTOKEN_POSITION_STRUCT_SLOT = accountVTokenPositionStructSlot(accountStructSlot(accountId), poolId);

        bytes32[] memory arr = new bytes32[](3);
        arr[0] = VTOKEN_POSITION_STRUCT_SLOT; // BALANCE
        arr[1] = VTOKEN_POSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_NET_TRADER_POSITION_OFFSET);
        arr[2] = VTOKEN_POSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_SUM_A_LAST_OFFSET);

        arr = clearingHouse.extsload(arr);

        balance = arr[0].toInt256();
        netTraderPosition = arr[1].toInt256();
        sumALastX128 = arr[2].toInt256();
    }

    struct TickRange {
        int24 tickLower;
        int24 tickUpper;
    }

    function getAccountPositionInfo(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 poolId
    )
        internal
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumALastX128,
            TickRange[] memory activeTickRanges
        )
    {
        bytes32 VTOKEN_POSITION_STRUCT_SLOT = accountVTokenPositionStructSlot(accountStructSlot(accountId), poolId);

        bytes32[] memory arr = new bytes32[](4);
        arr[0] = VTOKEN_POSITION_STRUCT_SLOT; // BALANCE
        arr[1] = VTOKEN_POSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_NET_TRADER_POSITION_OFFSET);
        arr[2] = VTOKEN_POSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_SUM_A_LAST_OFFSET);
        arr[3] = VTOKEN_POSITION_STRUCT_SLOT.offset(ACCOUNT_VTOKENPOSITION_LIQUIDITY_ACTIVE_OFFSET);

        arr = clearingHouse.extsload(arr);

        balance = arr[0].toInt256();
        netTraderPosition = arr[1].toInt256();
        sumALastX128 = arr[2].toInt256();
        activeTickRanges = convertToTickRangeArray(arr[3]);
    }

    function getAccountLiquidityPositionList(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 poolId
    ) internal view returns (TickRange[] memory activeTickRanges) {
        return
            convertToTickRangeArray(
                clearingHouse.extsload(
                    accountVTokenPositionStructSlot(accountStructSlot(accountId), poolId).offset(
                        ACCOUNT_VTOKENPOSITION_LIQUIDITY_ACTIVE_OFFSET
                    )
                )
            );
    }

    function getAccountLiquidityPositionInfo(
        IClearingHouse clearingHouse,
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (
            uint8 limitOrderType,
            uint128 liquidity,
            int256 vTokenAmountIn,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        bytes32 LIQUIDITY_POSITION_STRUCT_SLOT = accountLiquidityPositionStructSlot(
            accountVTokenPositionStructSlot(accountStructSlot(accountId), poolId),
            tickLower,
            tickUpper
        );

        bytes32[] memory arr = new bytes32[](6);
        arr[0] = LIQUIDITY_POSITION_STRUCT_SLOT; // BALANCE
        arr[1] = LIQUIDITY_POSITION_STRUCT_SLOT.offset(ACCOUNT_TP_LP_VTOKEN_AMOUNTIN_OFFSET);
        arr[2] = LIQUIDITY_POSITION_STRUCT_SLOT.offset(ACCOUNT_TP_LP_SUM_A_LAST_OFFSET);
        arr[3] = LIQUIDITY_POSITION_STRUCT_SLOT.offset(ACCOUNT_TP_LP_SUM_B_LAST_OFFSET);
        arr[4] = LIQUIDITY_POSITION_STRUCT_SLOT.offset(ACCOUNT_TP_LP_SUM_FP_LAST_OFFSET);
        arr[5] = LIQUIDITY_POSITION_STRUCT_SLOT.offset(ACCOUNT_TP_LP_SUM_FEE_LAST_OFFSET);

        arr = clearingHouse.extsload(arr);

        WordHelper.Word memory slot0 = arr[0].copyToMemory();
        limitOrderType = slot0.popUint8();
        slot0.pop(48); // discard 48 bits
        liquidity = slot0.popUint128();
        vTokenAmountIn = arr[1].toInt256();
        sumALastX128 = arr[2].toInt256();
        sumBInsideLastX128 = arr[3].toInt256();
        sumFpInsideLastX128 = arr[4].toInt256();
        sumFeeInsideLastX128 = arr[5].toUint256();
    }

    function convertToUint32Array(bytes32 active) internal pure returns (uint32[] memory activeArr) {
        unchecked {
            uint256 i = 8;
            while (i > 0) {
                bytes32 id = active.slice((i - 1) * 32, i * 32);
                if (id == ZERO) {
                    break;
                }
                i--;
            }
            activeArr = new uint32[](8 - i);
            while (i < 8) {
                activeArr[7 - i] = active.slice(i * 32, (i + 1) * 32).toUint32();
                i++;
            }
        }
    }

    function convertToTickRangeArray(bytes32 active) internal pure returns (TickRange[] memory activeArr) {
        unchecked {
            uint256 i = 5;
            while (i > 0) {
                bytes32 id = active.slice((i - 1) * 48, i * 48);
                if (id == ZERO) {
                    break;
                }
                i--;
            }
            activeArr = new TickRange[](5 - i);
            while (i < 5) {
                (int24 tickLower, int24 tickUpper) = Uint48Lib.unconcat(active.slice(i * 48, (i + 1) * 48).toUint48());
                activeArr[4 - i].tickLower = tickLower;
                activeArr[4 - i].tickUpper = tickUpper;
                i++;
            }
        }
    }
}
