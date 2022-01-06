//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import { Account, LiquidationParams } from './Account.sol';
import { LiquidityPosition, LimitOrderType } from './LiquidityPosition.sol';
import { LiquidityPositionSet, LiquidityChangeParams } from './LiquidityPositionSet.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';

import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

/// @notice swaps params for specifying the swap params
/// @param amount amount of tokens/base to swap
/// @param sqrtPriceLimit threshold sqrt price which if crossed then revert or execute partial swap
/// @param isNotional specifies whether the amount represents token amount (false) or base amount(true)
/// @param isPartialAllowed specifies whether to revert (false) or to execute a partial swap (true)
struct SwapParams {
    int256 amount;
    uint160 sqrtPriceLimit;
    bool isNotional;
    bool isPartialAllowed;
}

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for VTokenAddress;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for Set;
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;

    error IncorrectUpdate();
    error DeactivationFailed(VTokenAddress);
    error TokenInactive(VTokenAddress vTokenAddress);

    /// @notice stores info for VTokenPositionSet
    /// @param accountNo serial number of the account this set belongs to
    /// @param active list of all active token truncated addresses
    /// @param positions mapping from truncated token addresses to VTokenPosition struct for that address
    struct Set {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint256 accountNo;
        uint32[8] active;
        mapping(uint32 => VTokenPosition.Position) positions;
        uint256[100] emptySlots; // reserved for adding variables when upgrading logic
    }

    /// @notice returns true if the set does not have any token position active
    /// @param set VTokenPositionSet
    /// @return _isEmpty
    function isEmpty(Set storage set) internal view returns (bool _isEmpty) {
        _isEmpty = set.active[0] == 0;
    }

    /// @notice returns true if range position is active for 'vTokenAddress'
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param constants platform constants
    /// @return isRangeActive
    function getIsTokenRangeActive(
        Set storage set,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal returns (bool isRangeActive) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, false, constants);
        isRangeActive = !vTokenPosition.liquidityPositions.isEmpty();
    }

    /// @notice returns account market value of active positions
    /// @param set VTokenPositionSet
    /// @param vTokenAddresses mapping from truncated token address to token address for all active tokens
    /// @param constants platform constants
    /// @return accountMarketValue
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

            //Value of token position for current vToken
            accountMarketValue += position.marketValue(vToken, constants);

            uint160 sqrtPriceX96 = vToken.getVirtualTwapSqrtPriceX96(constants);
            //Value of all active range position for the current vToken
            accountMarketValue += int256(position.liquidityPositions.baseValue(sqrtPriceX96, vToken, constants));
        }

        //Value of the base token balance
        accountMarketValue += set.positions[VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()].balance;
    }

    /// @notice returns the max of two int256 numbers
    /// @param a first number
    /// @param b second number
    /// @return c  = max of a and b
    function max(int256 a, int256 b) internal pure returns (int256 c) {
        if (a > b) c = a;
        else c = b;
    }

    /// @notice returns notional value of the given base and token amounts
    /// @param vTokenAddress address of the token
    /// @param vTokenAmount amount of tokens
    /// @param vBaseAmount amount of base
    /// @param constants platform constants
    /// @return notionalAmountClosed for the given token and base amounts
    function getNotionalValue(
        VTokenAddress vTokenAddress,
        int256 vTokenAmount,
        int256 vBaseAmount,
        Constants memory constants
    ) internal view returns (int256 notionalAmountClosed) {
        notionalAmountClosed =
            vTokenAmount.abs().mulDiv(vTokenAddress.getVirtualTwapPriceX128(constants), FixedPoint128.Q128) +
            vBaseAmount.abs();
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param vTokenAddress address of the token
    /// @param constants platform constants
    /// @return longSideRisk - risk if the token price goes down
    /// @return shortSideRisk - risk if the token price goes up
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

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param vTokenAddresses mapping from truncated token address to token address for all active tokens
    /// @param constants platform constants
    /// @return requiredMargin - required margin value based on the current active positions
    function getRequiredMargin(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256 requiredMargin) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            VTokenAddress vTokenAddress = vTokenAddresses[set.active[i]];
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(isInitialMargin, vTokenAddress, constants);

            if (vTokenAddress.getWhitelisted(constants)) {
                longSideRiskTotal += longSideRisk;
                shortSideRiskTotal += shortSideRisk;
            } else {
                requiredMargin += max(longSideRisk, shortSideRisk);
            }
        }

        requiredMargin += max(longSideRiskTotal, shortSideRiskTotal);
    }

    /// @notice activates token with address 'vTokenAddress' if not already active
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    function activate(Set storage set, VTokenAddress vTokenAddress) internal {
        set.active.include(vTokenAddress.truncate());
    }

    /// @notice deactivates token with address 'vTokenAddress'
    /// @dev ensures that the balance is 0 and there are not range positions active otherwise throws an error
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    function deactivate(Set storage set, VTokenAddress vTokenAddress) internal {
        uint32 truncated = vTokenAddress.truncate();
        if (set.positions[truncated].balance != 0 && !set.positions[truncated].liquidityPositions.isEmpty()) {
            revert DeactivationFailed(vTokenAddress);
        }

        set.active.exclude(truncated);
    }

    /// @notice updates token balance, net trader position and base balance
    /// @dev realizes funding payment to base balance if vTokenAddress is not for base
    /// @dev activates the token if not already active
    /// @dev deactivates the token if the balance = 0 and there are no range positions active
    /// @param set VTokenPositionSet
    /// @param balanceAdjustments platform constants
    /// @param vTokenAddress address of the token
    /// @param constants platform constants
    function update(
        Set storage set,
        Account.BalanceAdjustments memory balanceAdjustments,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal {
        uint32 truncated = vTokenAddress.truncate();
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            set.realizeFundingPayment(vTokenAddress, constants);
            set.active.include(truncated);
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncated];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[
            VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()
        ];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0 && _VTokenPosition.liquidityPositions.active[0] == 0) {
            set.deactivate(vTokenAddress);
        }
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param constants platform constants
    function realizeFundingPayment(
        Set storage set,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal {
        set.realizeFundingPayment(vTokenAddress, vTokenAddress.vPoolWrapper(constants), constants);
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param constants platform constants
    function realizeFundingPayment(
        Set storage set,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[vTokenAddress.truncate()];
        int256 extrapolatedSumAX128 = wrapper.getSumAX128();

        VTokenPosition.Position storage _VBasePosition = set.positions[
            VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()
        ];
        int256 fundingPayment = _VTokenPosition.unrealizedFundingPayment(wrapper);
        _VBasePosition.balance += fundingPayment;

        _VTokenPosition.sumAX128Ckpt = extrapolatedSumAX128;

        emit Account.FundingPayment(set.accountNo, vTokenAddress, 0, 0, fundingPayment);
    }

    /// @notice get or create token position
    /// @dev activates inactive vToken if isCreateNew is true else reverts
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param createNew if 'vTokenAddress' is inactive then activates (true) else reverts with TokenInactive(false)
    /// @param constants platform constants
    /// @return position - VTokenPosition corresponding to 'vTokenAddress'
    function getTokenPosition(
        Set storage set,
        VTokenAddress vTokenAddress,
        bool createNew,
        Constants memory constants
    ) internal returns (VTokenPosition.Position storage position) {
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            if (createNew) {
                set.activate(vTokenAddress);
            } else if (!set.active.exists(vTokenAddress.truncate())) {
                revert TokenInactive(vTokenAddress);
            }
        }

        position = set.positions[vTokenAddress.truncate()];
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param swapParams parameters for swap
    /// @param constants platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return set.swapToken(vTokenAddress, swapParams, vTokenAddress.vPoolWrapper(constants), constants);
    }

    /// @notice swaps tokens (Long and Short) with input in token amount
    /// @dev activates inactive vToe
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param vTokenAmount amount of the token
    /// @param constants platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapTokenAmount(
        Set storage set,
        VTokenAddress vTokenAddress,
        int256 vTokenAmount,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            set.swapToken(
                vTokenAddress,
                ///@dev 0 means no price limit and false means amount mentioned is token amount
                SwapParams(vTokenAmount, 0, false, false),
                vTokenAddress.vPoolWrapper(constants),
                constants
            );
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param constants platform constants
    function removeLimitOrder(
        Set storage set,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        Constants memory constants
    ) internal {
        set.removeLimitOrder(vTokenAddress, tickLower, tickUpper, vTokenAddress.vPoolWrapper(constants), constants);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            set.liquidityChange(vTokenAddress, liquidityChangeParams, vTokenAddress.vPoolWrapper(constants), constants);
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param constants platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) internal returns (int256 notionalAmountClosed) {
        return set.liquidateLiquidityPositions(vTokenAddress, vTokenAddress.vPoolWrapper(constants), constants);
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param vTokenAddresses mapping from truncated token address to token address for all active tokens
    /// @param constants platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal returns (int256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]], constants);
        }
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of the token
    /// @param swapParams parameters for swap
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param constants platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        VTokenAddress vTokenAddress,
        SwapParams memory swapParams,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        // TODO: remove this after testing
        // console.log('Amount In:');
        // console.logInt(swapParams.amount);

        // console.log('Is Notional:');
        // console.log(swapParams.isNotional);

        (vTokenAmountOut, vBaseAmountOut) = wrapper.swapToken(
            swapParams.amount,
            swapParams.sqrtPriceLimit,
            swapParams.isNotional
        );
        //Change direction basis uniswap to balance increase
        vTokenAmountOut = -vTokenAmountOut;
        vBaseAmountOut = -vBaseAmountOut;
        // TODO: remove this after testing
        // console.log('Token Amount Out:');
        // console.logInt(vTokenAmountOut);

        // console.log('VBase Amount Out:');
        // console.logInt(vBaseAmountOut);
        Account.BalanceAdjustments memory balanceAdjustments = Account.BalanceAdjustments(
            vBaseAmountOut,
            vTokenAmountOut,
            vTokenAmountOut
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        emit Account.TokenPositionChange(set.accountNo, vTokenAddress, vTokenAmountOut, vBaseAmountOut);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        VTokenAddress vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, true, constants);

        Account.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.liquidityChange(
            set.accountNo,
            vTokenAddress,
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        if (liquidityChangeParams.closeTokenPosition) {
            set.swapTokenAmount(vTokenAddress, -balanceAdjustments.traderPositionIncrease, constants);
        }

        return (balanceAdjustments.vTokenIncrease, balanceAdjustments.vBaseIncrease);
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param constants platform constants
    function removeLimitOrder(
        Set storage set,
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vTokenAddress, false, constants);

        Account.BalanceAdjustments memory balanceAdjustments;
        int24 currentTick = vTokenAddress.getVirtualTwapTick(constants);

        vTokenPosition.liquidityPositions.removeLimitOrder(
            set.accountNo,
            vTokenAddress,
            currentTick,
            tickLower,
            tickUpper,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param vTokenAddress address of token
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param constants platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        VTokenAddress vTokenAddress,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 notionalAmountClosed) {
        Account.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vTokenAddress, false, constants).liquidityPositions.closeAllLiquidityPositions(
            set.accountNo,
            vTokenAddress,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vTokenAddress, constants);

        return
            getNotionalValue(
                vTokenAddress,
                balanceAdjustments.vTokenIncrease,
                balanceAdjustments.vBaseIncrease,
                constants
            );
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param vTokenAddresses mapping from truncated token address to token address for all active tokens
    /// @param constants platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        IVPoolWrapper wrapper,
        Constants memory constants
    ) internal returns (int256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokenAddresses[set.active[i]], wrapper, constants);
        }
    }
}
