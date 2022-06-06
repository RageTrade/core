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

library ClearingHouseExtsload {
    // Terminology:
    // SLOT is a storage location value which can be sloaded, typed in bytes32.
    // OFFSET is an slot offset value which should not be sloaded, henced typed in uint256.

    using WordHelper for bytes32;
    using WordHelper for WordHelper.Word;

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
}
