//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
import { VBASE_ADDRESS } from '../Constants.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';

import { Account } from './Account.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { VToken, VTokenLib } from '../libraries/VTokenLib.sol';

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for VToken;

    error IncorrectUpdate();

    struct Set {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => VTokenPosition.Position) positions;
    }

    function getAllTokenPositionValueAndMargin(Set storage set, bool isInitialMargin)
        internal
        view
        returns (int256 accountMarketValue, int256 totalRequiredMargin)
    {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];

            if (truncated == 0) break;
            VTokenPosition.Position storage position = set.positions[truncated];
            uint256 price = position.vToken.getVirtualTwapPrice();
            uint16 marginRatio = position.vToken.getMarginRatio(isInitialMargin);

            int256 tokenPosition = position.balance;
            int256 liquidityMaxTokenPosition = int256(
                LiquidityPositionSet.maxNetPosition(position.liquidityPositions, position.vToken)
            );

            if (-2 * tokenPosition < liquidityMaxTokenPosition) {
                totalRequiredMargin +=
                    (abs(tokenPosition + liquidityMaxTokenPosition) * int256(price) * int16(marginRatio)) /
                    int256(FixedPoint96.Q96);
            } else {
                totalRequiredMargin +=
                    (abs(tokenPosition) * int256(price) * int16(marginRatio)) /
                    int256(FixedPoint96.Q96);
            }

            accountMarketValue += VTokenPosition.getTokenPositionValue(position, price); // TODO consider removing this JUMP, as it's a simple multiplication
            uint160 sqrtPrice = position.vToken.getVirtualTwapSqrtPrice();
            accountMarketValue += int256(
                LiquidityPositionSet.baseValue(position.liquidityPositions, sqrtPrice, position.vToken)
            );
            accountMarketValue += VTokenPosition.getTokenPositionValue(set.positions[truncate(VBASE_ADDRESS)], (price)); // ? TODO consider removing this
        }

        return (accountMarketValue, totalRequiredMargin);
    }

    function activate(Set storage set, address vTokenAddress) internal {
        set.active.include(truncate(vTokenAddress));
        VTokenPosition.Position storage position = set.positions[truncate(vTokenAddress)];
        VTokenPosition.initialize(position, VToken.wrap(vTokenAddress));
    }

    function update(
        Account.BalanceAdjustments memory balanceAdjustments,
        Set storage set,
        address vTokenAddress
    ) internal {
        if (vTokenAddress != VBASE_ADDRESS) {
            set.active.include(truncate(vTokenAddress));
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(VBASE_ADDRESS)];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;
    }

    function realizeFundingPaymentToAccount(Set storage set, address vTokenAddress) internal returns (int256) {
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        int256 extrapolatedSumA = int256(_VTokenPosition.vToken.vPoolWrapper().getExtrapolatedSumA());

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(VBASE_ADDRESS)];
        _VBasePosition.balance -= _VTokenPosition.netTraderPosition * (extrapolatedSumA - _VTokenPosition.sumAChkpt);

        _VTokenPosition.sumAChkpt = extrapolatedSumA;
        return _VBasePosition.balance;
    }

    function abs(int256 value) internal pure returns (int256) {
        if (value < 0) return value * -1;
        else return value;
    }

    function truncate(address _add) internal pure returns (uint32) {
        return uint32(uint160(_add));
    }
}
