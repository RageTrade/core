//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from './Account.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';
import { PoolIdHelper } from './PoolIdHelper.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPositionSet {
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for Info;
    using Uint48L5ArrayLib for uint48[5];
    using PoolIdHelper for uint32;

    struct Info {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // concat(tickLow,tickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error IllegalTicks(int24 tickLower, int24 tickUpper);
    error DeactivationFailed(int24 tickLower, int24 tickUpper, uint256 liquidity);
    error InactiveRange();

    function isEmpty(Info storage set) internal view returns (bool) {
        return set.active[0] == 0;
    }

    function isPositionActive(
        Info storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (bool) {
        return _exists(set.active, tickLower, tickUpper);
    }

    function baseValue(
        Info storage set,
        uint160 sqrtPriceCurrent,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 baseValue_) {
        baseValue_ = set.baseValue(sqrtPriceCurrent, poolId.vPoolWrapper(protocol));
    }

    function baseValue(
        Info storage set,
        uint160 sqrtPriceCurrent,
        IVPoolWrapper wrapper // TODO refactor this
    ) internal view returns (int256 baseValue_) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            if (id == 0) break;
            baseValue_ += set.positions[id].baseValue(sqrtPriceCurrent, wrapper);
        }
    }

    function maxNetPosition(Info storage set) internal view returns (uint256 risk) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].maxNetPosition();
        }
    }

    function getLiquidityPosition(
        Info storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = Uint48Lib.concat(tickLower, tickUpper);
        position = set.positions[positionId];

        if (!position.isInitialized()) revert InactiveRange();
        return position;
    }

    function activate(
        Info storage set,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = _include(set.active, tickLower, tickUpper);
        position = set.positions[positionId];

        if (!position.isInitialized()) {
            position.initialize(tickLower, tickUpper);
        }
    }

    function deactivate(Info storage set, LiquidityPosition.Info storage position) internal {
        if (position.liquidity != 0) {
            revert DeactivationFailed(position.tickLower, position.tickUpper, position.liquidity);
        }

        _exclude(set.active, position.tickLower, position.tickUpper);
    }

    function _include(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private returns (uint48 index) {
        array.include(index = Uint48Lib.concat(val1, val2));
    }

    function _exclude(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private returns (uint48 index) {
        array.exclude(index = Uint48Lib.concat(val1, val2));
    }

    function _exists(
        uint48[5] storage array,
        int24 val1,
        int24 val2
    ) private view returns (bool) {
        return array.exists(Uint48Lib.concat(val1, val2));
    }

    function liquidityChange(
        Info storage set,
        uint256 accountNo,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position = set.activate(
            liquidityChangeParams.tickLower,
            liquidityChangeParams.tickUpper
        );

        position.limitOrderType = liquidityChangeParams.limitOrderType;

        set.liquidityChange(
            accountNo,
            poolId,
            position,
            liquidityChangeParams.liquidityDelta,
            wrapper,
            balanceAdjustments
        );
    }

    function liquidityChange(
        Info storage set,
        uint256 accountNo,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        position.liquidityChange(accountNo, poolId, liquidity, wrapper, balanceAdjustments);

        emit Account.LiquidityTokenPositionChange(
            accountNo,
            poolId,
            position.tickLower,
            position.tickUpper,
            balanceAdjustments.vTokenIncrease
        );

        if (position.liquidity == 0) {
            set.deactivate(position);
        }
    }

    function closeLiquidityPosition(
        Info storage set,
        uint256 accountNo,
        uint32 poolId,
        LiquidityPosition.Info storage position,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        set.liquidityChange(accountNo, poolId, position, -int128(position.liquidity), wrapper, balanceAdjustments);
    }

    function removeLimitOrder(
        Info storage set,
        uint256 accountNo,
        uint32 poolId,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position = set.getLiquidityPosition(tickLower, tickUpper);
        position.checkValidLimitOrderRemoval(currentTick);
        set.closeLiquidityPosition(accountNo, poolId, position, wrapper, balanceAdjustments);
    }

    function closeAllLiquidityPositions(
        Info storage set,
        uint256 accountNo,
        uint32 poolId,
        IVPoolWrapper wrapper,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position;

        while (set.active[0] != 0) {
            IClearingHouseStructures.BalanceAdjustments memory balanceAdjustmentsCurrent;

            position = set.positions[set.active[0]];

            set.closeLiquidityPosition(accountNo, poolId, position, wrapper, balanceAdjustmentsCurrent);

            balanceAdjustments.vBaseIncrease += balanceAdjustmentsCurrent.vBaseIncrease;
            balanceAdjustments.vTokenIncrease += balanceAdjustmentsCurrent.vTokenIncrease;
            balanceAdjustments.traderPositionIncrease += balanceAdjustmentsCurrent.traderPositionIncrease;
        }
    }

    function getInfo(Info storage set)
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

    function getNetPosition(Info storage set, uint160 sqrtPriceCurrent) internal view returns (int256 netPosition) {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            netPosition += set.positions[set.active[i]].netPosition(sqrtPriceCurrent);
        }
    }
}
