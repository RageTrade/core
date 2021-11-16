//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { Account, LiquidationParams } from './Account.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { LiquidityPositionSet, LiquidityChangeParams } from './LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { SafeCast } from './uniswap/SafeCast.sol';
import { FullMath } from './FullMath.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { Constants } from '../Constants.sol';

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for Set;
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using SafeCast for uint256;
    using FullMath for int256;

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
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 accountMarketValue, int256 totalRequiredMargin) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;
            VTokenAddress vToken = VTokenAddress.wrap(vTokenAddresses[truncated]);
            VTokenPosition.Position storage position = set.positions[truncated];
            uint256 price = vToken.getVirtualTwapPrice(constants);
            uint16 marginRatio = vToken.getMarginRatio(isInitialMargin, constants);

            int256 tokenPosition = position.balance;
            int256 liquidityMaxTokenPosition = int256(
                LiquidityPositionSet.maxNetPosition(position.liquidityPositions, vToken, constants)
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

            accountMarketValue += VTokenPosition.marketValue(position, vToken, price, constants); // TODO consider removing this JUMP, as it's a simple multiplication
            uint160 sqrtPrice = vToken.getVirtualTwapSqrtPrice(constants);
            accountMarketValue += int256(
                LiquidityPositionSet.baseValue(position.liquidityPositions, sqrtPrice, vToken, constants)
            );
            accountMarketValue += VTokenPosition.marketValue(
                set.positions[truncate(constants.VBASE_ADDRESS)],
                vToken,
                price,
                constants
            ); // ? TODO consider removing this
        }

        return (accountMarketValue, totalRequiredMargin);
    }

    function getAccountMarketValue(Set storage set, mapping(uint32 => address) storage vTokenAddresses)
        internal
        view
        returns (int256 accountMarketValue)
    {
        //TODO
    }

    function getRequiredMarginWithExclusion(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses,
        address vTokenAddressToSkip
    ) internal view returns (int256 requiredMargin, int256 requiredMarginOther) {
        //TODO
    }

    function getRequiredMargin(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses
    ) internal view returns (int256 requiredMargin) {
        int256 requiredMarginOther;
        (requiredMargin, requiredMarginOther) = set.getRequiredMarginWithExclusion(
            isInitialMargin,
            vTokenAddresses,
            address(0)
        );
        return requiredMargin;
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
        address vTokenAddress,
        Constants memory constants
    ) internal {
        if (vTokenAddress != constants.VBASE_ADDRESS) {
            set.active.include(truncate(vTokenAddress)); // TODO : We can do truncate at once at the top and save it in mem
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(constants.VBASE_ADDRESS)];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0) {
            set.deactivate(vTokenAddress);
        }
    }

    function realizeFundingPayment(
        Set storage set,
        address vTokenAddress,
        Constants memory constants
    ) internal {
        realizeFundingPayment(set, vTokenAddress, VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants), constants);
    }

    function realizeFundingPayment(
        Set storage set,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            set.realizeFundingPayment(vTokenAddresses[truncated], constants);
        }
    }

    function realizeFundingPayment(
        Set storage set,
        address vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        int256 extrapolatedSumA = wrapper.getExtrapolatedSumA();

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(constants.VBASE_ADDRESS)];
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

    function getTokenPosition(
        Set storage set,
        address vTokenAddress,
        Constants memory constants
    ) internal returns (VTokenPosition.Position storage) {
        if (vTokenAddress != constants.VBASE_ADDRESS) {
            set.activate(vTokenAddress);
        }

        VTokenPosition.Position storage position = set.positions[truncate(vTokenAddress)];

        return position;
    }

    function swapTokenAmount(
        Set storage set,
        address vTokenAddress,
        int256 vTokenAmount,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.swapTokenAmount(
                vTokenAddress,
                vTokenAmount,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function swapTokenNotional(
        Set storage set,
        address vTokenAddress,
        int256 vTokenNotional,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.swapTokenNotional(
                vTokenAddress,
                vTokenNotional,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.liquidityChange(
                vTokenAddress,
                position,
                liquidity,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.liquidityChange(
                vTokenAddress,
                liquidityChangeParams,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function liquidateLiquidityPositions(Set storage set, address vTokenAddress) internal returns (int256) {
        set.liquidateLiquidityPositions(vTokenAddress, VTokenAddress.wrap(vTokenAddress).vPoolWrapper());
    }

    function liquidateLiquidityPositions(Set storage set, mapping(uint32 => address) storage vTokenAddresses)
        internal
        returns (int256)
    {
        int256 notionalAmountClosed;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]]);
        }

        return notionalAmountClosed;
    }

    function swapTokenAmount(
        Set storage set,
        address vTokenAddress,
        int256 vTokenAmount,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        int256 vBaseAmount = wrapper.swapTokenAmount(vTokenAmount);
        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            vBaseAmount,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return vBaseAmount;
    }

    function swapTokenNotional(
        Set storage set,
        address vTokenAddress,
        int256 vTokenNotional,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        int256 vTokenAmount = wrapper.swapTokenNotional(vTokenNotional);

        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            -1 * vTokenNotional,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return vTokenNotional;
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, constants).liquidityPositions.liquidityChange(
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice(constants).toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function liquidityChange(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        int128 liquidity,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, constants).liquidityPositions.liquidityChange(
            position,
            liquidity,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice(constants).toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        address vTokenAddress,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        LiquidityPositionSet.Info storage liquidityPositions = set.getTokenPosition(vTokenAddress).liquidityPositions;

        LiquidityPosition.Info storage position;

        while (liquidityPositions.active[0] != 0) {
            position = liquidityPositions.positions[liquidityPositions.active[0]];
            liquidityPositions.liquidityChange(position, -1 * int128(position.liquidity), wrapper, balanceAdjustments);
        }

        set.update(balanceAdjustments, vTokenAddress);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPrice().toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper
    ) internal returns (int256) {
        int256 notionalAmountClosed;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]], wrapper);
        }

        return notionalAmountClosed;
    }

    function getTokenPositionToLiquidate(
        Set storage set,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        mapping(uint32 => address) storage vTokenAddresses
    )
        internal
        returns (
            int256,
            int256,
            int256
        )
    {
        int256 accountMarketValue;
        int256 totalRequiredMargin;
        int256 totalRequiredMarginOther;

        accountMarketValue = set.getAccountMarketValue(vTokenAddresses);

        (totalRequiredMargin, totalRequiredMarginOther) = set.getRequiredMarginWithExclusion(
            false,
            vTokenAddresses,
            vTokenAddress
        );

        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress);

        VTokenAddress vToken = VTokenAddress.wrap(vTokenAddress);
        int256 tokensToTrade = (accountMarketValue -
            liquidationParams.fixFee.toInt256() -
            (totalRequiredMarginOther +
                (vToken.getVirtualTwapPrice().toInt256() * vTokenPosition.balance).mulDiv(
                    vToken.getMarginRatio(false),
                    1e5
                )).mulDiv(liquidationParams.targetMarginRatio, 1e1));

        return (tokensToTrade, accountMarketValue, totalRequiredMargin);
    }
}
