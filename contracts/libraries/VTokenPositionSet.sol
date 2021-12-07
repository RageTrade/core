//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';
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

import { console } from 'hardhat/console.sol';

struct SwapParams {
    int256 amount;
    uint160 sqrtPriceLimit;
    bool isNotional;
}

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
    error DeactivationFailed(VTokenAddress);
    error TokenInactive(address vTokenAddress);

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
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 accountMarketValue) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;
            VTokenAddress vToken = vTokenAddresses[truncated];
            VTokenPosition.Position storage position = set.positions[truncated];

            accountMarketValue += position.marketValue(vToken, constants);

            uint160 sqrtPriceX96 = vToken.getVirtualTwapSqrtPriceX96(constants);
            accountMarketValue += int256(position.liquidityPositions.baseValue(sqrtPriceX96, vToken, constants));
        }
        //TODO: Remove logs
        // console.log('Base value:');
        // console.logInt(set.positions[truncate(constants.VBASE_ADDRESS)].balance);
        accountMarketValue += set.positions[VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()].balance;

        return (accountMarketValue);
    }

    function max(int256 a, int256 b) internal pure returns (int256 c) {
        if (a > b) c = a;
        else c = b;
    }

    function getLongShortSideRisk(
        Set storage set,
        bool isInitialMargin,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal view returns (int256 longSideRisk, int256 shortSideRisk) {
        VTokenPosition.Position storage position = set.positions[vTokenAddress.truncate()];

        uint256 price = vTokenAddress.getVirtualTwapPriceX128(constants);
        uint16 marginRatio = vTokenAddress.getMarginRatio(isInitialMargin, constants);

        int256 tokenPosition = position.balance;
        int256 liquidityMaxTokenPosition = int256(position.liquidityPositions.maxNetPosition(vTokenAddress, constants));

        longSideRisk = max(tokenPosition + liquidityMaxTokenPosition, 0).mulDiv(price, FixedPoint128.Q128).mulDiv(
            marginRatio,
            1e5
        );

        shortSideRisk = max(-tokenPosition, 0).mulDiv(price, FixedPoint128.Q128).mulDiv(marginRatio, 1e5);
        return (longSideRisk, shortSideRisk);
    }

    function getRequiredMarginWithExclusion(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        VTokenAddress vTokenAddressToSkip,
        Constants memory constants
    ) internal view returns (int256 requiredMargin, int256 requiredMarginOther) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            if (vTokenAddresses[set.active[i]].eq(vTokenAddressToSkip)) continue;
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(
                isInitialMargin,
                vTokenAddresses[set.active[i]],
                constants
            );

            longSideRiskTotal += longSideRisk;
            shortSideRiskTotal += shortSideRisk;
        }

        requiredMarginOther = max(longSideRiskTotal, shortSideRiskTotal);
        if (!vTokenAddressToSkip.eq(address(0))) {
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
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 requiredMargin) {
        int256 requiredMarginOther;
        (requiredMargin, requiredMarginOther) = set.getRequiredMarginWithExclusion(
            isInitialMargin,
            vTokenAddresses,
            VTokenAddress.wrap(address(0)),
            constants
        );
        return requiredMargin;
    }

    function activate(Set storage set, VTokenAddress vTokenAddress) internal {
        set.active.include(vTokenAddress.truncate());
    }

    function deactivate(Set storage set, VTokenAddress vTokenAddress) internal {
        uint32 truncated = vTokenAddress.truncate();
        if (set.positions[truncated].balance != 0) {
            revert DeactivationFailed(vTokenAddress);
        }

        set.active.exclude(truncated);
    }

    function update(
        Set storage set,
        Account.BalanceAdjustments memory balanceAdjustments,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal {
        uint32 truncated = vTokenAddress.truncate();
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            set.active.include(truncated);
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncated];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[
            VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()
        ];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0) {
            set.deactivate(vTokenAddress);
        }
    }

    function realizeFundingPayment(
        Set storage set,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal {
        set.realizeFundingPayment(vTokenAddress, vTokenAddress.vPoolWrapper(constants), constants);
    }

    function realizeFundingPayment(
        Set storage set,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[vTokenAddress.truncate()];
        int256 extrapolatedSumA = wrapper.getSumAX128();

        VTokenPosition.Position storage _VBasePosition = set.positions[
            VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()
        ];
        int256 fundingPayment = _VTokenPosition.netTraderPosition * (extrapolatedSumA - _VTokenPosition.sumAChkpt);
        _VBasePosition.balance -= fundingPayment;

        _VTokenPosition.sumAChkpt = extrapolatedSumA;

        emit Account.FundingPayment(set.accountNo, vTokenAddress, 0, 0, fundingPayment);
    }

    function abs(int256 value) internal pure returns (int256) {
        if (value < 0) return value * -1;
        else return value;
    }

    function getTokenPosition(
        Set storage set,
        VTokenAddress vTokenAddress,
        bool createNew,
        Constants memory constants
    ) internal returns (VTokenPosition.Position storage) {
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            if (createNew) {
                set.activate(vTokenAddress);
            } else if (set.positions[truncate(vTokenAddress)].balance == 0) {
                revert TokenInactive(vTokenAddress);
            }
        }

        VTokenPosition.Position storage position = set.positions[vTokenAddress.truncate()];

        return position;
    }

    function swapToken(
        Set storage set,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        Constants memory constants
    ) internal returns (int256, int256) {
        return set.swapToken(vTokenAddress, swapParams, vTokenAddress.vPoolWrapper(constants), constants);
    }

    function swapTokenAmount(
        Set storage set,
        VTokenAddress vTokenAddress,
        int256 vTokenAmount,
        Constants memory constants
    ) internal returns (int256, int256) {
        return
            set.swapToken(
                vTokenAddress,
                ///@dev 0 means no price limit and false means amount mentioned is token amount
                SwapParams(vTokenAmount, 0, false),
                vTokenAddress.vPoolWrapper(constants),
                constants
            );
    }

    function closeLiquidityPosition(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityPosition.Info storage position,
        Constants memory constants
    ) internal returns (int256) {
        return set.closeLiquidityPosition(vTokenAddress, position, vTokenAddress.vPoolWrapper(constants), constants);
    }

    function liquidityChange(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        Constants memory constants
    ) internal returns (int256) {
        return
            set.liquidityChange(vTokenAddress, liquidityChangeParams, vTokenAddress.vPoolWrapper(constants), constants);
    }

    function liquidateLiquidityPositions(
        Set storage set,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal returns (int256) {
        return set.liquidateLiquidityPositions(vTokenAddress, vTokenAddress.vPoolWrapper(constants), constants);
    }

    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
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

    function swapToken(
        Set storage set,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256, int256) {
        set.realizeFundingPayment(vTokenAddress, constants);
        // TODO: remove this after testing
        // console.log('Amount In:');
        // console.logInt(swapParams.amount);

        // console.log('Is Notional:');
        // console.log(swapParams.isNotional);

        (int256 vTokenAmount, int256 vBaseAmount) = wrapper.swapToken(
            swapParams.amount,
            swapParams.sqrtPriceLimit,
            swapParams.isNotional
        );
        // TODO: remove this after testing
        // console.log('Token Amount Out:');
        // console.logInt(vTokenAmount);

        // console.log('VBase Amount Out:');
        // console.logInt(vBaseAmount);
        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            vBaseAmount,
            vTokenAmount,
            vTokenAmount
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        emit Account.TokenPositionChange(set.accountNo, vTokenAddress, vTokenAmount, vBaseAmount);

        return (vTokenAmount, vBaseAmount);
    }

    function liquidityChange(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, true, constants);

        Account.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.liquidityChange(
            set.accountNo,
            vTokenAddress,
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );
        // TODO: remove this after testing
        // console.log('Token Amount Out:');
        // console.logInt(balanceAdjustments.vTokenIncrease);

        // console.log('VBase Amount Out:');
        // console.logInt(balanceAdjustments.vBaseIncrease);

        if (liquidityChangeParams.closeTokenPosition && balanceAdjustments.vTokenIncrease > 0) {
            set.swapTokenAmount(vTokenAddress, -balanceAdjustments.vTokenIncrease, constants);
            balanceAdjustments.vTokenIncrease = 0;
        }

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease.mulDiv(
                VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants),
                FixedPoint128.Q128
            ) + balanceAdjustments.vBaseIncrease;
    }

    function closeLiquidityPosition(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityPosition.Info storage position,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, false, constants);

        Account.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.closeLiquidityPosition(
            set.accountNo,
            vTokenAddress,
            position,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease.mulDiv(
                VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants),
                FixedPoint128.Q128
            ) + balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, false, constants).liquidityPositions.closeAllLiquidityPositions(
            set.accountNo,
            vTokenAddress,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            balanceAdjustments.vTokenIncrease.mulDiv(
                VTokenAddress.wrap(vTokenAddress).getVirtualTwapPriceX128(constants),
                FixedPoint128.Q128
            ) + balanceAdjustments.vBaseIncrease;
    }

    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
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
}
