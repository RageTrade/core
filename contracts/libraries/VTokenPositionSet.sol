//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint128 } from './uniswap/FixedPoint128.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { Account, LiquidationParams } from './Account.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { LiquidityPositionSet, LiquidityChangeParams } from './LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { SafeCast } from './uniswap/SafeCast.sol';
import { FullMath } from './FullMath.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { Constants } from '../utils/Constants.sol';

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for VTokenAddress;
    using VTokenPosition for VTokenPosition.Position;
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
        uint256 accountNo;
        uint32[8] active;
        mapping(uint32 => VTokenPosition.Position) positions;
    }

    function getAccountMarketValue(
        Set storage set,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 accountMarketValue) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;
            VTokenAddress vToken = VTokenAddress.wrap(vTokenAddresses[truncated]);
            VTokenPosition.Position storage position = set.positions[truncated];

            accountMarketValue += position.marketValue(vToken, constants);

            uint160 sqrtPriceX96 = vToken.getVirtualTwapSqrtPriceX96(constants);
            accountMarketValue += int256(position.liquidityPositions.baseValue(sqrtPriceX96, vToken, constants));
        }

        accountMarketValue += set.positions[truncate(constants.VBASE_ADDRESS)].balance;

        return (accountMarketValue);
    }

    function max(int256 a, int256 b) internal pure returns (int256 c) {
        if (a > b) c = a;
        else c = b;
    }

    function getLongShortSideRisk(
        Set storage set,
        bool isInitialMargin,
        address vTokenAddress,
        Constants memory constants
    ) internal view returns (int256 longSideRisk, int256 shortSideRisk) {
        VTokenAddress vToken = VTokenAddress.wrap(vTokenAddress);
        VTokenPosition.Position storage position = set.positions[truncate(vTokenAddress)];

        uint256 price = vToken.getVirtualTwapPriceX128(constants);
        uint16 marginRatio = vToken.getMarginRatio(isInitialMargin, constants);

        int256 tokenPosition = position.balance;
        int256 liquidityMaxTokenPosition = int256(position.liquidityPositions.maxNetPosition(vToken, constants));

        longSideRisk =
            (max(tokenPosition + liquidityMaxTokenPosition, 0) * int256(price)).mulDiv(marginRatio, 1e5) /
            int256(FixedPoint128.Q128);

        shortSideRisk = (max(-tokenPosition, 0) * int256(price)).mulDiv(marginRatio, 1e5) / int256(FixedPoint128.Q128);
        return (longSideRisk, shortSideRisk);
    }

    function getRequiredMarginWithExclusion(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses,
        address vTokenAddressToSkip,
        Constants memory constants
    ) internal view returns (int256 requiredMargin, int256 requiredMarginOther) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            if (vTokenAddresses[set.active[i]] == vTokenAddressToSkip) continue;
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(
                isInitialMargin,
                vTokenAddresses[set.active[i]],
                constants
            );

            longSideRiskTotal += longSideRisk;
            shortSideRiskTotal += shortSideRisk;
        }

        requiredMarginOther = max(longSideRiskTotal, shortSideRiskTotal);
        if (vTokenAddressToSkip != address(0)) {
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(isInitialMargin, vTokenAddressToSkip, constants);
            longSideRiskTotal += longSideRisk;
            shortSideRiskTotal += shortSideRisk;
        }

        requiredMargin = max(longSideRiskTotal, shortSideRiskTotal);
        return (requiredMargin, requiredMarginOther);
    }

    function getRequiredMargin(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 requiredMargin) {
        int256 requiredMarginOther;
        (requiredMargin, requiredMarginOther) = set.getRequiredMarginWithExclusion(
            isInitialMargin,
            vTokenAddresses,
            address(0),
            constants
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
        set.realizeFundingPayment(vTokenAddress, VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants), constants);
    }

    function realizeFundingPayment(
        Set storage set,
        address vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncate(vTokenAddress)];
        int256 extrapolatedSumA = wrapper.getSumAX128();

        VTokenPosition.Position storage _VBasePosition = set.positions[truncate(constants.VBASE_ADDRESS)];
        int256 fundingPayment = _VTokenPosition.netTraderPosition * (extrapolatedSumA - _VTokenPosition.sumAChkpt);
        _VBasePosition.balance -= fundingPayment;

        _VTokenPosition.sumAChkpt = extrapolatedSumA;

        emit Account.FundingPayment(set.accountNo, vTokenAddress, 0, 0, fundingPayment);
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
    ) internal returns (int256, int256) {
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
    ) internal returns (int256, int256) {
        return
            set.swapTokenNotional(
                vTokenAddress,
                vTokenNotional,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function closeLiquidityPosition(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.closeLiquidityPosition(
                vTokenAddress,
                position,
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

    function liquidateLiquidityPositions(
        Set storage set,
        address vTokenAddress,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.liquidateLiquidityPositions(
                vTokenAddress,
                VTokenAddress.wrap(vTokenAddress).vPoolWrapper(constants),
                constants
            );
    }

    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256) {
        int256 notionalAmountClosed;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]], constants);
        }

        return notionalAmountClosed;
    }

    function swapTokenAmount(
        Set storage set,
        address vTokenAddress,
        int256 vTokenAmount,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256, int256) {
        set.realizeFundingPayment(vTokenAddress, constants);

        int256 vBaseAmount = wrapper.swapTokenAmount(vTokenAmount);
        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            vBaseAmount,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        emit Account.TokenPositionChange(set.accountNo, vTokenAddress, vTokenAmount, vBaseAmount);

        return (vTokenAmount, vBaseAmount);
    }

    function swapTokenNotional(
        Set storage set,
        address vTokenAddress,
        int256 vTokenNotional,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256, int256) {
        set.realizeFundingPayment(vTokenAddress, constants);

        int256 vTokenAmount = wrapper.swapTokenNotional(vTokenNotional);

        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            -vTokenNotional,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress, constants);
        emit Account.TokenPositionChange(set.accountNo, vTokenAddress, vTokenAmount, -vTokenNotional);

        return (vTokenAmount, -vTokenNotional);
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
            set.accountNo,
            vTokenAddress,
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );

        if (liquidityChangeParams.closeTokenPosition && balanceAdjustments.vTokenIncrease > 0) {
            set.swapTokenAmount(vTokenAddress, -balanceAdjustments.vTokenIncrease, constants);
            balanceAdjustments.vTokenIncrease = 0;
        }

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants).toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function closeLiquidityPosition(
        Set storage set,
        address vTokenAddress,
        LiquidityPosition.Info storage position,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, constants).liquidityPositions.closeLiquidityPosition(
            set.accountNo,
            vTokenAddress,
            position,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants).toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        address vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, constants).liquidityPositions.closeAllLiquidityPositions(
            set.accountNo,
            vTokenAddress,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease *
            VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants).toInt256() +
            balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => address) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        int256 notionalAmountClosed;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]], wrapper, constants);
        }

        return notionalAmountClosed;
    }

    function getTokenPositionToLiquidate(
        Set storage set,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        mapping(uint32 => address) storage vTokenAddresses,
        Constants memory constants
    )
        internal
        returns (
            int256 tokensToTrade,
            int256 accountMarketValue,
            int256 totalRequiredMargin
        )
    {
        int256 totalRequiredMarginOther;

        accountMarketValue = set.getAccountMarketValue(vTokenAddresses, constants);

        (totalRequiredMargin, totalRequiredMarginOther) = set.getRequiredMarginWithExclusion(
            false,
            vTokenAddresses,
            vTokenAddress,
            constants
        );

        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, constants);

        VTokenAddress vToken = VTokenAddress.wrap(vTokenAddress);
        tokensToTrade = (accountMarketValue -
            liquidationParams.fixFee.toInt256() -
            (totalRequiredMarginOther +
                (vToken.getVirtualTwapPriceX128(constants).toInt256() * vTokenPosition.balance).mulDiv(
                    vToken.getMarginRatio(false, constants),
                    1e5
                )).mulDiv(liquidationParams.targetMarginRatio, 1e1));

        return (tokensToTrade, accountMarketValue, totalRequiredMargin);
    }
}
