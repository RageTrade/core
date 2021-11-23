//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { Uint48Lib } from './Uint48.sol';
import { Uint48L5ArrayLib } from './Uint48L5Array.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { Account } from './Account.sol';

import { Constants } from '../utils/Constants.sol';

struct LiquidityChangeParams {
    int24 tickLower;
    int24 tickUpper;
    int128 liquidity;
    LimitOrderType limitOrderType;
}

library LiquidityPositionSet {
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for Info;
    using Uint48L5ArrayLib for uint48[5];
    using VTokenLib for VTokenAddress;

    error IllegalTicks(int24 tickLower, int24 tickUpper);
    error DeactivationFailed(int24 tickLower, int24 tickUpper, uint256 liquidity);

    struct Info {
        // multiple per pool because it's non-fungible, allows for 4 billion LP positions lifetime
        uint48[5] active;
        // concat(tickLow,tickHigh)
        mapping(uint48 => LiquidityPosition.Info) positions;
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
        Constants memory constants
    ) internal view returns (uint256 baseValue_) {
        baseValue_ = set.baseValue(sqrtPriceCurrent, vToken, vToken.vPoolWrapper(constants), constants);
    }

    function baseValue(
        Info storage set,
        uint160 sqrtPriceCurrent,
        VTokenAddress vToken,
        IVPoolWrapper wrapper, // TODO refactor this
        Constants memory constants
    ) internal view returns (uint256 baseValue_) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            baseValue_ += set.positions[id].baseValue(sqrtPriceCurrent, vToken, wrapper, constants);
        }
    }

    function maxNetPosition(
        Info storage set,
        VTokenAddress vToken,
        Constants memory constants
    ) internal view returns (uint256 risk) {
        for (uint256 i = 0; i < set.active.length; i++) {
            uint48 id = set.active[i];
            risk += set.positions[id].maxNetPosition(vToken, constants);
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

        require(position.isInitialized());
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
        LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        LiquidityPosition.Info storage position = set.activate(
            liquidityChangeParams.tickLower,
            liquidityChangeParams.tickUpper
        );

        position.limitOrderType = liquidityChangeParams.limitOrderType;

        set.liquidityChange(position, liquidityChangeParams.liquidity, wrapper, balanceAdjustments);
    }

    function liquidityChange(
        Info storage set,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper,
        Account.BalanceAdjustments memory balanceAdjustments
    ) internal {
        position.liquidityChange(liquidity, wrapper, balanceAdjustments);

        if (position.liquidity == 0) {
            set.deactivate(position);
        }
    }
}
