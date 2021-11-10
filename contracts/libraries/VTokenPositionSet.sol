//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
import { VBASE_ADDRESS } from '../Constants.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { Account } from './Account.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for Set;
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;

    error IncorrectUpdate();
    error DeactivationFailed(address);

    struct Set {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => VTokenPosition.Position) positions;
    }

    function getAllTokenPositionValueAndMargin(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];

            if (truncated == 0) break;
            VTokenAddress vToken = VTokenAddress.wrap(vTokenAddresses[truncated]);
            VTokenPosition.Position storage position = set.positions[truncated];
            uint256 price = vToken.getVirtualTwapPrice();
            uint16 marginRatio = vToken.getMarginRatio(isInitialMargin);

            int256 tokenPosition = position.balance;
            int256 liquidityMaxTokenPosition = int256(
                LiquidityPositionSet.maxNetPosition(position.liquidityPositions, vToken)
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

            accountMarketValue += VTokenPosition.marketValue(position, vToken, price); // TODO consider removing this JUMP, as it's a simple multiplication
            uint160 sqrtPrice = vToken.getVirtualTwapSqrtPrice();
            accountMarketValue += int256(
                LiquidityPositionSet.baseValue(position.liquidityPositions, sqrtPrice, vToken)
            );
            accountMarketValue += VTokenPosition.marketValue(set.positions[truncate(VBASE_ADDRESS)], vToken, price); // ? TODO consider removing this
        }

        return (accountMarketValue, totalRequiredMargin);
    }

    function activate(Set storage set, address vTokenAddress) internal {
        set.active.include(truncate(vTokenAddress));
    }

    function deactivate(Set storage set, address vTokenAddress) internal {
        if (set.positions[truncate(vTokenAddress)].balance != 0) {
            revert DeactivationFailed(vTokenAddress);
        }

        set.active.exclude(truncate(vTokenAddress));
    }

    function update(
        Set storage set,
        Account.BalanceAdjustments memory balanceAdjustments,
        address vTokenAddress
    ) internal {
        if (vTokenAddress != VBASE_ADDRESS) {
            set.active.include(truncate(vTokenAddress)); // TODO : We can do truncate at once at the top and save it in mem
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(VBASE_ADDRESS)];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0) {
            set.deactivate(vTokenAddress);
        }
    }

    function realizeFundingPayment(Set storage set, address vTokenAddress) internal {
        realizeFundingPayment(set, vTokenAddress, VTokenAddress.wrap(vTokenAddress).vPoolWrapper());
    }

    function realizeFundingPayment(
        Set storage set,
        address vTokenAddress,
        IVPoolWrapper wrapper
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        int256 extrapolatedSumA = wrapper.getExtrapolatedSumA();

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(VBASE_ADDRESS)];
        _VBasePosition.balance -= _VTokenPosition.netTraderPosition * (extrapolatedSumA - _VTokenPosition.sumAChkpt);

        _VTokenPosition.sumAChkpt = extrapolatedSumA;
    }

    function abs(int256 value) internal pure returns (int256) {
        if (value < 0) return value * -1;
        else return value;
    }

    function truncate(address _add) internal pure returns (uint32) {
        return uint32(uint160(_add));
    }

    function getTokenPosition(Set storage set, address vTokenAddress)
        internal
        returns (VTokenPosition.Position storage)
    {
        if (vTokenAddress != VBASE_ADDRESS) {
            set.activate(vTokenAddress);
        }

        VTokenPosition.Position storage position = set.positions[truncate(vTokenAddress)];

        return position;
    }

    function swapTokenAmount(
        Set storage set,
        address vTokenAddress,
        int256 vTokenAmount
    ) internal returns (int256) {
        return set.swapTokenAmount(vTokenAddress, vTokenAmount, VTokenAddress.wrap(vTokenAddress).vPoolWrapper());
    }

    function swapTokenNotional(
        Set storage set,
        address vTokenAddress,
        int256 vTokenNotional
    ) internal returns (int256) {
        return set.swapTokenNotional(vTokenAddress, vTokenNotional, VTokenAddress.wrap(vTokenAddress).vPoolWrapper());
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        int128 liquidity
    ) internal returns (int256) {
        return
            set.liquidityChange(vTokenAddress, position, liquidity, VTokenAddress.wrap(vTokenAddress).vPoolWrapper());
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        LimitOrderType limitOrderType
    ) internal returns (int256) {
        return
            set.liquidityChange(
                vTokenAddress,
                tickLower,
                tickUpper,
                liquidity,
                limitOrderType,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper()
            );
    }

    function swapTokenAmount(
        Set storage set,
        address vTokenAddress,
        int256 vTokenAmount,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        int256 vBaseAmount = wrapper.swapTokenAmount(vTokenAmount);
        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            vBaseAmount,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress);

        return vBaseAmount;
    }

    function swapTokenNotional(
        Set storage set,
        address vTokenAddress,
        int256 vTokenNotional,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        int256 vTokenAmount = wrapper.swapTokenNotional(vTokenNotional);

        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            -1 * vTokenNotional,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress);

        return vTokenNotional;
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        LimitOrderType limitOrderType,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress);

        LiquidityPosition.Info storage position = vTokenPosition.liquidityPositions.activate(tickLower, tickUpper);

        int256 vBaseIncrease = set.liquidityChange(vTokenAddress, position, liquidity, wrapper);

        if (position.liquidity == 0) {
            vTokenPosition.liquidityPositions.deactivate(position);
        } else {
            position.limitOrderType = limitOrderType;
        }

        return vBaseIncrease;
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        position.liquidityChange(liquidity, wrapper, balanceAdjustments);

        set.update(balanceAdjustments, vTokenAddress);

        return balanceAdjustments.vBaseIncrease;
    }
}
