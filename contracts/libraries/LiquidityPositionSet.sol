// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { LiquidityPosition } from './LiquidityPosition.sol';
import { Protocol } from './Protocol.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

/// @title Liquidity position set functions
library LiquidityPositionSet {
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;
    using Uint48Lib for int24;
    using Uint48Lib for uint48;
    using Uint48L5ArrayLib for uint48[5];

    error LPS_IllegalTicks(int24 tickLower, int24 tickUpper);
    error LPS_DeactivationFailed(int24 tickLower, int24 tickUpper, uint256 liquidity);
    error LPS_InactiveRange();

    /// @notice denotes token position change due to liquidity add/remove
    /// @param accountId serial number of the account
    /// @param poolId address of token whose position was taken
    /// @param tickLower lower tick of the range updated
    /// @param tickUpper upper tick of the range updated
    /// @param vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    event TokenPositionChangedDueToLiquidityChanged(
        uint256 indexed accountId,
        uint32 indexed poolId,
        int24 tickLower,
        int24 tickUpper,
        int256 vTokenAmountOut
    );

    /**
     *  Internal methods
     */

    /// @notice activates a position by initializing it and adding it to the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param tickLower lower tick of the range to be activated
    /// @param tickUpper upper tick of the range to be activated
    /// @return position storage ref of the activated position
    function activate(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert LPS_IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId;
        set.active.include(positionId = tickLower.concat(tickUpper));
        position = set.positions[positionId];

        if (!position.isInitialized()) {
            position.initialize(tickLower, tickUpper);
        }
    }

    /// @notice deactivates a position by removing it from the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param position storage ref to the position to be deactivated
    function deactivate(LiquidityPosition.Set storage set, LiquidityPosition.Info storage position) internal {
        if (position.liquidity != 0) {
            revert LPS_DeactivationFailed(position.tickLower, position.tickUpper, position.liquidity);
        }

        set.active.exclude(position.tickLower.concat(position.tickUpper));
    }

    /// @notice changes liquidity of a position in the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vToken
    /// @param liquidityChangeParams parameters of the liquidity change
    /// @param balanceAdjustments adjustments to made to the account's balance later
    /// @param protocol ref to the state of the protocol
    function liquidityChange(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position = set.activate(
            liquidityChangeParams.tickLower,
            liquidityChangeParams.tickUpper
        );

        position.limitOrderType = liquidityChangeParams.limitOrderType;

        set.liquidityChange(
            accountId,
            poolId,
            position,
            liquidityChangeParams.liquidityDelta,
            balanceAdjustments,
            protocol
        );
    }

    /// @notice changes liquidity of a position in the set
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vToken
    /// @param position storage ref to the position to be changed
    /// @param liquidityDelta amount of liquidity to be added or removed
    /// @param balanceAdjustments adjustments to made to the account's balance later
    /// @param protocol ref to the state of the protocol
    function liquidityChange(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        int128 liquidityDelta,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        position.liquidityChange(accountId, poolId, liquidityDelta, balanceAdjustments, protocol);

        emit TokenPositionChangedDueToLiquidityChanged(
            accountId,
            poolId,
            position.tickLower,
            position.tickUpper,
            balanceAdjustments.vTokenIncrease
        );

        if (position.liquidity == 0) {
            set.deactivate(position);
        }
    }

    /// @notice removes liquidity from a position in the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vToken
    /// @param position storage ref to the position to be closed
    /// @param balanceAdjustments adjustments to made to the account's balance later
    /// @param protocol ref to the state of the protocol
    function closeLiquidityPosition(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        set.liquidityChange(accountId, poolId, position, -int128(position.liquidity), balanceAdjustments, protocol);
    }

    /// @notice removes liquidity from a position in the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vToken
    /// @param currentTick current tick of the pool
    /// @param tickLower lower tick of the range to be closed
    /// @param tickUpper upper tick of the range to be closed
    /// @param balanceAdjustments adjustments to made to the account's balance later
    /// @param protocol ref to the state of the protocol
    function removeLimitOrder(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position = set.getLiquidityPosition(tickLower, tickUpper);
        position.checkValidLimitOrderRemoval(currentTick);
        set.closeLiquidityPosition(accountId, poolId, position, balanceAdjustments, protocol);
    }

    /// @notice removes liquidity from all the positions in the set
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param accountId serial number of the account
    /// @param poolId truncated address of vToken
    /// @param balanceAdjustments adjustments to made to the account's balance later
    /// @param protocol ref to the state of the protocol
    function closeAllLiquidityPositions(
        LiquidityPosition.Set storage set,
        uint256 accountId,
        uint32 poolId,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        Protocol.Info storage protocol
    ) internal {
        LiquidityPosition.Info storage position;

        while (set.active[0] != 0) {
            IClearingHouseStructures.BalanceAdjustments memory balanceAdjustmentsCurrent;

            position = set.positions[set.active[0]];

            set.closeLiquidityPosition(accountId, poolId, position, balanceAdjustmentsCurrent, protocol);

            balanceAdjustments.vQuoteIncrease += balanceAdjustmentsCurrent.vQuoteIncrease;
            balanceAdjustments.vTokenIncrease += balanceAdjustmentsCurrent.vTokenIncrease;
            balanceAdjustments.traderPositionIncrease += balanceAdjustmentsCurrent.traderPositionIncrease;
        }
    }

    /**
     *  Internal view methods
     */

    /// @notice gets the liquidity position of a tick range
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param tickLower lower tick of the range to be closed
    /// @param tickUpper upper tick of the range to be closed
    /// @return position liquidity position of the tick range
    function getLiquidityPosition(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert LPS_IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = Uint48Lib.concat(tickLower, tickUpper);
        position = set.positions[positionId];

        if (!position.isInitialized()) revert LPS_InactiveRange();
        return position;
    }

    /// @notice gets information about all the liquidity position
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @return liquidityPositions Information about all the liquidity position for the pool
    function getInfo(LiquidityPosition.Set storage set)
        internal
        view
        returns (IClearingHouseStructures.LiquidityPositionView[] memory liquidityPositions)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        liquidityPositions = new IClearingHouseStructures.LiquidityPositionView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            liquidityPositions[i].limitOrderType = set.positions[set.active[i]].limitOrderType;
            liquidityPositions[i].tickLower = set.positions[set.active[i]].tickLower;
            liquidityPositions[i].tickUpper = set.positions[set.active[i]].tickUpper;
            liquidityPositions[i].liquidity = set.positions[set.active[i]].liquidity;
            liquidityPositions[i].vTokenAmountIn = set.positions[set.active[i]].vTokenAmountIn;
            liquidityPositions[i].sumALastX128 = set.positions[set.active[i]].sumALastX128;
            liquidityPositions[i].sumBInsideLastX128 = set.positions[set.active[i]].sumBInsideLastX128;
            liquidityPositions[i].sumFpInsideLastX128 = set.positions[set.active[i]].sumFpInsideLastX128;
            liquidityPositions[i].sumFeeInsideLastX128 = set.positions[set.active[i]].sumFeeInsideLastX128;
        }
    }

    /// @notice gets the net position due to all the liquidity positions
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param sqrtPriceCurrent current sqrt price of the pool
    /// @return netPosition due to all the liquidity positions
    function getNetPosition(LiquidityPosition.Set storage set, uint160 sqrtPriceCurrent)
        internal
        view
        returns (int256 netPosition)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            netPosition += set.positions[set.active[i]].netPosition(sqrtPriceCurrent);
        }
    }

    /// @notice checks whether the liquidity position set is empty
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @return true if the liquidity position set is empty
    function isEmpty(LiquidityPosition.Set storage set) internal view returns (bool) {
        return set.active.isEmpty();
    }

    /// @notice checks whether for given ticks, a liquidity position is active
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param tickLower lower tick of the range
    /// @param tickUpper upper tick of the range
    /// @return true if the liquidity position is active
    function isPositionActive(
        LiquidityPosition.Set storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (bool) {
        return set.active.exists(tickLower.concat(tickUpper));
    }

    /// @notice gets the total long side risk for all the active liquidity positions
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param valuationPriceX96 price used to value the vToken asset
    /// @return risk the net long side risk for all the active liquidity positions
    function longSideRisk(LiquidityPosition.Set storage set, uint160 valuationPriceX96)
        internal
        view
        returns (uint256 risk)
    {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].longSideRisk(valuationPriceX96);
        }
    }

    /// @notice gets the total market value of all the active liquidity positions
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @param sqrtPriceCurrent price used to value the vToken asset
    /// @param poolId the id of the pool
    /// @param protocol ref to the state of the protocol
    /// @return marketValue_ the total market value of all the active liquidity positions
    function marketValue(
        LiquidityPosition.Set storage set,
        uint160 sqrtPriceCurrent,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256 marketValue_) {
        marketValue_ = set.marketValue(sqrtPriceCurrent, protocol.vPoolWrapper(poolId));
    }

    /// @notice Get the total market value of all active liquidity positions in the set.
    /// @param set: Collection of active liquidity positions
    /// @param sqrtPriceCurrent: Current price of the virtual asset
    /// @param wrapper: address of the wrapper contract, passed once to avoid multiple sloads for wrapper
    function marketValue(
        LiquidityPosition.Set storage set,
        uint160 sqrtPriceCurrent,
        IVPoolWrapper wrapper
    ) internal view returns (int256 marketValue_) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            if (id == 0) break;
            marketValue_ += set.positions[id].marketValue(sqrtPriceCurrent, wrapper);
        }
    }

    /// @notice gets the max net position possible due to all the liquidity positions
    /// @param set storage ref to the account's set of liquidity positions of a pool
    /// @return risk the max net position possible due to all the liquidity positions
    function maxNetPosition(LiquidityPosition.Set storage set) internal view returns (uint256 risk) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].maxNetPosition();
        }
    }
}
