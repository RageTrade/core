//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from './Account.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { AccountStorage } from '../protocol/clearinghouse/ClearingHouseStorage.sol';

import { console } from 'hardhat/console.sol';

struct LiquidityChangeParams {
    int24 tickLower;
    int24 tickUpper;
    int128 liquidityDelta;
    uint160 sqrtPriceCurrent;
    uint16 slippageToleranceBps;
    bool closeTokenPosition;
    LimitOrderType limitOrderType;
}

library LiquidityPositionSet {
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for Info;
    using Uint48L5ArrayLib for uint48[5];
    using VTokenLib for VTokenAddress;

    error IllegalTicks(int24 tickLower, int24 tickUpper);
    error DeactivationFailed(int24 tickLower, int24 tickUpper, uint256 liquidity);
    error InactiveRange();

    struct Info {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // concat(tickLow,tickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
        uint256[100] emptySlots; // reserved for adding variables when upgrading logic
    }

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
        VTokenAddress vToken,
        AccountStorage storage accountStorage
    ) internal view returns (int256 baseValue_) {
        baseValue_ = set.baseValue(sqrtPriceCurrent, vToken.vPoolWrapper(accountStorage));
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
    ) internal returns (LiquidityPosition.Info storage position) {
        if (tickLower > tickUpper) {
            revert IllegalTicks(tickLower, tickUpper);
        }

        uint48 positionId = _include(set.active, tickLower, tickUpper);
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
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position = set.activate(
            liquidityChangeParams.tickLower,
            liquidityChangeParams.tickUpper
        );

        position.limitOrderType = liquidityChangeParams.limitOrderType;

        set.liquidityChange(
            accountNo,
            vTokenAddress,
            position,
            liquidityChangeParams.liquidityDelta,
            wrapper,
            balanceAdjustments
        );
    }

    function liquidityChange(
        Info storage set,
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        position.liquidityChange(accountNo, vTokenAddress, liquidity, wrapper, balanceAdjustments);

        emit Account.LiquidityTokenPositionChange(
            accountNo,
            vTokenAddress,
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
        VTokenAddress vTokenAddress,
        LiquidityPosition.Info storage position,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        set.liquidityChange(
            accountNo,
            vTokenAddress,
            position,
            -int128(position.liquidity),
            wrapper,
            balanceAdjustments
        );
    }

    function removeLimitOrder(
        Info storage set,
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position = set.getLiquidityPosition(tickLower, tickUpper);
        position.checkValidLimitOrderRemoval(currentTick);
        set.closeLiquidityPosition(accountNo, vTokenAddress, position, wrapper, balanceAdjustments);
    }

    function closeAllLiquidityPositions(
        Info storage set,
        uint256 accountNo,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position;

        while (set.active[0] != 0) {
            Account.BalanceAdjustments memory balanceAdjustmentsCurrent;

            position = set.positions[set.active[0]];

            set.closeLiquidityPosition(accountNo, vTokenAddress, position, wrapper, balanceAdjustmentsCurrent);

            balanceAdjustments.vBaseIncrease += balanceAdjustmentsCurrent.vBaseIncrease;
            balanceAdjustments.vTokenIncrease += balanceAdjustmentsCurrent.vTokenIncrease;
            balanceAdjustments.traderPositionIncrease += balanceAdjustmentsCurrent.traderPositionIncrease;
        }
    }
}
