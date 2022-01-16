//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from './Account.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { VTokenLib } from './VTokenLib.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { console } from 'hardhat/console.sol';

library VTokenPositionSet {
    using Uint32L8ArrayLib for uint32[8];
    using VTokenLib for IVToken;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for Set;
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;

    error IncorrectUpdate();
    error DeactivationFailed(IVToken);
    error TokenInactive(IVToken vToken);

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
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    /// @notice returns true if the set does not have any token position active
    /// @param set VTokenPositionSet
    /// @return _isEmpty
    function isEmpty(Set storage set) internal view returns (bool _isEmpty) {
        _isEmpty = set.active[0] == 0;
    }

    /// @notice returns true if range position is active for 'vToken'
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param protocol platform constants
    /// @return isRangeActive
    function getIsTokenRangeActive(
        Set storage set,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    ) internal returns (bool isRangeActive) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vToken, false, protocol);
        isRangeActive = !vTokenPosition.liquidityPositions.isEmpty();
    }

    /// @notice returns account market value of active positions
    /// @param set VTokenPositionSet
    /// @param vTokens mapping from truncated token address to token address for all active tokens
    /// @param protocol platform constants
    /// @return accountMarketValue
    function getAccountMarketValue(
        Set storage set,
        mapping(uint32 => IVToken) storage vTokens,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 accountMarketValue) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;
            IVToken vToken = vTokens[truncated];
            VTokenPosition.Position storage position = set.positions[truncated];

            //Value of token position for current vToken
            accountMarketValue += position.marketValue(vToken, protocol);

            uint160 sqrtPriceX96 = vToken.getVirtualTwapSqrtPriceX96(protocol);
            //Value of all active range position for the current vToken
            accountMarketValue += int256(position.liquidityPositions.baseValue(sqrtPriceX96, vToken, protocol));
        }

        //Value of the base token balance
        accountMarketValue += set.positions[IVToken(address(protocol.vBase)).truncate()].balance;
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
    /// @param vToken address of the token
    /// @param vTokenAmount amount of tokens
    /// @param vBaseAmount amount of base
    /// @param protocol platform constants
    /// @return notionalAmountClosed for the given token and base amounts
    function getNotionalValue(
        IVToken vToken,
        int256 vTokenAmount,
        int256 vBaseAmount,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 notionalAmountClosed) {
        notionalAmountClosed =
            vTokenAmount.abs().mulDiv(vToken.getVirtualTwapPriceX128(protocol), FixedPoint128.Q128) +
            vBaseAmount.abs();
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param vToken address of the token
    /// @param protocol platform constants
    /// @return longSideRisk - risk if the token price goes down
    /// @return shortSideRisk - risk if the token price goes up
    function getLongShortSideRisk(
        Set storage set,
        bool isInitialMargin,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 longSideRisk, int256 shortSideRisk) {
        VTokenPosition.Position storage position = set.positions[vToken.truncate()];

        uint256 price = vToken.getVirtualTwapPriceX128(protocol);
        uint16 marginRatio = vToken.getMarginRatio(isInitialMargin, protocol);

        int256 tokenPosition = position.balance;
        int256 liquidityMaxTokenPosition = int256(position.liquidityPositions.maxNetPosition());

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
    /// @param vTokens mapping from truncated token address to token address for all active tokens
    /// @param protocol platform constants
    /// @return requiredMargin - required margin value based on the current active positions
    function getRequiredMargin(
        Set storage set,
        bool isInitialMargin,
        mapping(uint32 => IVToken) storage vTokens,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 requiredMargin) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            IVToken vToken = vTokens[set.active[i]];
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(isInitialMargin, vToken, protocol);

            if (vToken.getWhitelisted(protocol)) {
                longSideRiskTotal += longSideRisk;
                shortSideRiskTotal += shortSideRisk;
            } else {
                requiredMargin += max(longSideRisk, shortSideRisk);
            }
        }

        requiredMargin += max(longSideRiskTotal, shortSideRiskTotal);
    }

    /// @notice activates token with address 'vToken' if not already active
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    function activate(Set storage set, IVToken vToken) internal {
        set.active.include(vToken.truncate());
    }

    /// @notice deactivates token with address 'vToken'
    /// @dev ensures that the balance is 0 and there are not range positions active otherwise throws an error
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    function deactivate(Set storage set, IVToken vToken) internal {
        uint32 truncated = vToken.truncate();
        if (set.positions[truncated].balance != 0 && !set.positions[truncated].liquidityPositions.isEmpty()) {
            revert DeactivationFailed(vToken);
        }

        set.active.exclude(truncated);
    }

    /// @notice updates token balance, net trader position and base balance
    /// @dev realizes funding payment to base balance if vToken is not for base
    /// @dev activates the token if not already active
    /// @dev deactivates the token if the balance = 0 and there are no range positions active
    /// @dev IMP: ensure that the global states are updated using zeroSwap or directly through some interaction with pool wrapper
    /// @param set VTokenPositionSet
    /// @param balanceAdjustments platform constants
    /// @param vToken address of the token
    /// @param protocol platform constants
    function update(
        Set storage set,
        IClearingHouse.BalanceAdjustments memory balanceAdjustments,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    ) internal {
        uint32 truncated = vToken.truncate();
        if (!vToken.eq(address(protocol.vBase))) {
            set.realizeFundingPayment(vToken, protocol);
            set.active.include(truncated);
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[truncated];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[IVToken(address(protocol.vBase)).truncate()];
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0 && _VTokenPosition.liquidityPositions.active[0] == 0) {
            set.deactivate(vToken);
        }
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param protocol platform constants
    function realizeFundingPayment(
        Set storage set,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    ) internal {
        set.realizeFundingPayment(vToken, protocol.pools[vToken].vPoolWrapper, protocol);
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    function realizeFundingPayment(
        Set storage set,
        IVToken vToken,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal {
        VTokenPosition.Position storage _VTokenPosition = set.positions[vToken.truncate()];
        int256 extrapolatedSumAX128 = wrapper.getSumAX128();

        VTokenPosition.Position storage _VBasePosition = set.positions[IVToken(address(protocol.vBase)).truncate()];
        int256 fundingPayment = _VTokenPosition.unrealizedFundingPayment(wrapper);
        _VBasePosition.balance += fundingPayment;

        _VTokenPosition.sumAX128Ckpt = extrapolatedSumAX128;

        emit Account.FundingPayment(set.accountNo, vToken, 0, 0, fundingPayment);
    }

    /// @notice get or create token position
    /// @dev activates inactive vToken if isCreateNew is true else reverts
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param createNew if 'vToken' is inactive then activates (true) else reverts with TokenInactive(false)
    /// @param protocol platform constants
    /// @return position - VTokenPosition corresponding to 'vToken'
    function getTokenPosition(
        Set storage set,
        IVToken vToken,
        bool createNew,
        Account.ProtocolInfo storage protocol
    ) internal returns (VTokenPosition.Position storage position) {
        if (!vToken.eq(address(protocol.vBase))) {
            if (createNew) {
                set.activate(vToken);
            } else if (!set.active.exists(vToken.truncate())) {
                revert TokenInactive(vToken);
            }
        }

        position = set.positions[vToken.truncate()];
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param swapParams parameters for swap
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        IVToken vToken,
        IClearingHouse.SwapParams memory swapParams,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return set.swapToken(vToken, swapParams, vToken.vPoolWrapper(protocol), protocol);
    }

    /// @notice swaps tokens (Long and Short) with input in token amount
    /// @dev activates inactive vToe
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param vTokenAmount amount of the token
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapTokenAmount(
        Set storage set,
        IVToken vToken,
        int256 vTokenAmount,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            set.swapToken(
                vToken,
                ///@dev 0 means no price limit and false means amount mentioned is token amount
                IClearingHouse.SwapParams(vTokenAmount, 0, false, false),
                vToken.vPoolWrapper(protocol),
                protocol
            );
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        Set storage set,
        IVToken vToken,
        int24 tickLower,
        int24 tickUpper,
        Account.ProtocolInfo storage protocol
    ) internal {
        set.removeLimitOrder(vToken, tickLower, tickUpper, vToken.vPoolWrapper(protocol), protocol);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        IVToken vToken,
        IClearingHouse.LiquidityChangeParams memory liquidityChangeParams,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            set.liquidityChange(vToken, liquidityChangeParams, vToken.vPoolWrapper(protocol), protocol);
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        IVToken vToken,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        return set.liquidateLiquidityPositions(vToken, vToken.vPoolWrapper(protocol), protocol);
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param vTokens mapping from truncated token address to token address for all active tokens
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => IVToken) storage vTokens,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokens[set.active[i]], protocol);
        }
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param vToken address of the token
    /// @param swapParams parameters for swap
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        IVToken vToken,
        IClearingHouse.SwapParams memory swapParams,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
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
        IClearingHouse.BalanceAdjustments memory balanceAdjustments = IClearingHouse.BalanceAdjustments(
            vBaseAmountOut,
            vTokenAmountOut,
            vTokenAmountOut
        );

        set.update(balanceAdjustments, vToken, protocol);

        emit Account.TokenPositionChange(set.accountNo, vToken, vTokenAmountOut, vBaseAmountOut);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        IVToken vToken,
        IClearingHouse.LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vToken, true, protocol);

        IClearingHouse.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.liquidityChange(
            set.accountNo,
            vToken,
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vToken, protocol);

        if (liquidityChangeParams.closeTokenPosition) {
            set.swapTokenAmount(vToken, -balanceAdjustments.traderPositionIncrease, protocol);
        }

        return (balanceAdjustments.vTokenIncrease, balanceAdjustments.vBaseIncrease);
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    function removeLimitOrder(
        Set storage set,
        IVToken vToken,
        int24 tickLower,
        int24 tickUpper,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(vToken, false, protocol);

        IClearingHouse.BalanceAdjustments memory balanceAdjustments;
        int24 currentTick = vToken.getVirtualTwapTick(protocol);

        vTokenPosition.liquidityPositions.removeLimitOrder(
            set.accountNo,
            vToken,
            currentTick,
            tickLower,
            tickUpper,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vToken, protocol);
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param vToken address of token
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        IVToken vToken,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        IClearingHouse.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(vToken, false, protocol).liquidityPositions.closeAllLiquidityPositions(
            set.accountNo,
            vToken,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, vToken, protocol);

        return
            getNotionalValue(
                vToken,
                balanceAdjustments.vTokenIncrease,
                balanceAdjustments.vBaseIncrease,
                protocol
            );
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param vTokens mapping from truncated token address to token address for all active tokens
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        mapping(uint32 => IVToken) storage vTokens,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(vTokens[set.active[i]], wrapper, protocol);
        }
    }
}
