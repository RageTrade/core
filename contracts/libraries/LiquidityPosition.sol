//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

library LiquidityPosition {
    using LiquidityPosition for Info;

    error AlreadyInitialized();

    struct Info {
        // the tick range of the position; TODO Is storing ticks needed as it's in the positionId?
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // funding payment checkpoints
        uint256 sumALast;
        uint256 sumBInsideLast;
        uint256 sumFpInsideLast;
        // the fee growth of the aggregate position as of the last action on the individual position
        // TODO since both of them are in vBase denomination, is a single fee var enough?
        // uint256 feeGrowthInsideLongsLastX128; // in uniswap's tick state
        // uint256 feeGrowthInsideShortsLastX128; // in wrapper's tick state
        uint256 longsFeeGrowthInsideLast;
        uint256 shortsFeeGrowthInsideLast;
    }

    function isInitialized(Info storage info) internal view returns (bool) {
        return info.tickLower != 0 || info.tickUpper != 0;
    }

    function initialize(
        Info storage info,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        if (info.isInitialized()) {
            revert AlreadyInitialized();
        }

        info.tickLower = tickLower;
        info.tickUpper = tickUpper;
    }

    function updateCheckpoints(
        Info storage info,
        IVPoolWrapper wrapper // TODO use vTokenLib
    ) internal {
        (
            uint256 sumALast,
            uint256 sumBInsideLast,
            uint256 sumFpInsideLast,
            uint256 longsFeeGrowthInsideLast,
            uint256 shortsFeeGrowthInsideLast
        ) = wrapper.getValuesInside(info.tickLower, info.tickUpper);

        info.sumALast = sumALast;
        info.sumBInsideLast = sumBInsideLast;
        info.sumFpInsideLast = sumFpInsideLast;
        info.longsFeeGrowthInsideLast = longsFeeGrowthInsideLast;
        info.shortsFeeGrowthInsideLast = shortsFeeGrowthInsideLast;
    }

    function netPosition(Info storage info, IVPoolWrapper wrapper) internal returns (uint256) {
        (, uint256 sumBInside, , , ) = wrapper.getValuesInside(info.tickLower, info.tickUpper);
        return (sumBInside - info.sumBInsideLast) * info.liquidity;
    }

    // function getMaxTokenPosition(info) {}

    // function getLiquidityPositionValue(info, sqrtPriceCurrent) returns (int96) {}

    // function realizeFundingPayment(Set storage set, account) internal {}

    // function liquidityChange(
    //     Set storage set,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidity
    // ) internal returns (uint256 vBaseBalanceChange, uint256 vTokenBalanceChange) {}
}
