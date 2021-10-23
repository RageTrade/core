//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { console } from 'hardhat/console.sol';

library LiquidityPosition {
    struct Info {
        // the tick range of the position
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInsideLongsLastX128; // in uniswap's tick state
        uint256 feeGrowthInsideShortsLastX128; // in wrapper's tick state
        // funding payment checkpoints
        uint256 sumAChkpt;
        uint256 sumBInsideChkpt;
        uint256 sumFpInsideChkpt;
    }

    // function getMaxTokenPosition(info) {}

    // function getLiquidityPositionValue(info, sqrtPriceCurrent) returns (int96) {}

    // function netPosition(Info info) {}

    // function realizeFundingPayment(Set storage set, account) internal {}

    // function liquidityChange(
    //     Set storage set,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint128 liquidity
    // ) internal returns (uint256 vBaseBalanceChange, uint256 vTokenBalanceChange) {}
}
