//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from './Account.sol';
import { AddressHelper } from './AddressHelper.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { SignedMath } from './SignedMath.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { PoolIdHelper } from './PoolIdHelper.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { console } from 'hardhat/console.sol';

library VTokenPositionSet {
    using AddressHelper for address;
    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using PoolIdHelper for uint32;
    using SafeCast for uint256;
    using SignedFullMath for int256;
    using SignedMath for int256;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for Set;
    using Uint32L8ArrayLib for uint32[8];

    // TODO include VTokenPositionSet in the name of these errors
    error IncorrectUpdate();
    error DeactivationFailed(uint32 poolId);
    error TokenInactive(uint32 poolId);

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
    /// @param poolId poolId of the vToken
    /// @param protocol platform constants
    /// @return isRangeActive
    function isTokenRangeActive(
        Set storage set,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal returns (bool isRangeActive) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(poolId, false, protocol);
        isRangeActive = !vTokenPosition.liquidityPositions.isEmpty();
    }

    /// @notice returns account market value of active positions
    /// @param set VTokenPositionSet
    /// @param protocol platform constants
    /// @return accountMarketValue
    function getAccountMarketValue(Set storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256 accountMarketValue)
    {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 poolId = set.active[i];
            if (poolId == 0) break;
            // IVToken vToken = protocol[poolId].vToken;
            VTokenPosition.Position storage position = set.positions[poolId];

            //Value of token position for current vToken
            accountMarketValue += position.marketValue(poolId, protocol);

            uint160 sqrtPriceX96 = poolId.getVirtualTwapSqrtPriceX96(protocol);
            //Value of all active range position for the current vToken
            accountMarketValue += position.liquidityPositions.baseValue(sqrtPriceX96, poolId, protocol);
        }

        //Value of the base token balance
        accountMarketValue += set.positions[address(protocol.vBase).truncate()].balance; // TODO ensure vToken truncated cannot be vBase truncated ever
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
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of tokens
    /// @param vBaseAmount amount of base
    /// @param protocol platform constants
    /// @return notionalAmountClosed for the given token and base amounts
    function getNotionalValue(
        uint32 poolId,
        int256 vTokenAmount,
        int256 vBaseAmount,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 notionalAmountClosed) {
        notionalAmountClosed =
            vTokenAmount.abs().mulDiv(poolId.getVirtualTwapPriceX128(protocol), FixedPoint128.Q128) +
            vBaseAmount.abs();
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    /// @return longSideRisk - risk if the token price goes down
    /// @return shortSideRisk - risk if the token price goes up
    function getLongShortSideRisk(
        Set storage set,
        bool isInitialMargin,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 longSideRisk, int256 shortSideRisk) {
        VTokenPosition.Position storage position = set.positions[poolId];

        uint256 price = poolId.getVirtualTwapPriceX128(protocol);
        uint16 marginRatio = poolId.getMarginRatio(isInitialMargin, protocol);

        int256 tokenPosition = position.balance;
        int256 longSideRiskRanges = position.liquidityPositions.longSideRisk(poolId, protocol).toInt256();

        longSideRisk = max(position.netTraderPosition.mulDiv(price, FixedPoint128.Q128) + longSideRiskRanges, 0).mulDiv(
                marginRatio,
                1e5
            );

        shortSideRisk = max(-tokenPosition, 0).mulDiv(price, FixedPoint128.Q128).mulDiv(marginRatio, 1e5);
        return (longSideRisk, shortSideRisk);
    }

    /// @notice returns the long and short side risk for range positions of a particular token
    /// @param set VTokenPositionSet
    /// @param isInitialMargin specifies to use initial margin factor (true) or maintainance margin factor (false)
    /// @param protocol platform constants
    /// @return requiredMargin - required margin value based on the current active positions
    function getRequiredMargin(
        Set storage set,
        bool isInitialMargin,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 requiredMargin) {
        int256 longSideRiskTotal;
        int256 shortSideRiskTotal;
        int256 longSideRisk;
        int256 shortSideRisk;
        for (uint8 i = 0; i < set.active.length; i++) {
            if (set.active[i] == 0) break;
            uint32 poolId = set.active[i];
            (longSideRisk, shortSideRisk) = set.getLongShortSideRisk(isInitialMargin, poolId, protocol);

            if (poolId.isCrossMargined(protocol)) {
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
    /// @param poolId id of the rage trade pool
    function activate(Set storage set, uint32 poolId) internal {
        set.active.include(poolId);
    }

    /// @notice deactivates token with address 'vToken'
    /// @dev ensures that the balance is 0 and there are not range positions active otherwise throws an error
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    function deactivate(Set storage set, uint32 poolId) internal {
        if (set.positions[poolId].balance != 0 || !set.positions[poolId].liquidityPositions.isEmpty()) {
            revert DeactivationFailed(poolId);
        }

        set.active.exclude(poolId);
    }

    /// @notice updates token balance, net trader position and base balance
    /// @dev realizes funding payment to base balance if vToken is not for base
    /// @dev activates the token if not already active
    /// @dev deactivates the token if the balance = 0 and there are no range positions active
    /// @dev IMP: ensure that the global states are updated using zeroSwap or directly through some interaction with pool wrapper
    /// @param set VTokenPositionSet
    /// @param balanceAdjustments platform constants
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    function update(
        Set storage set,
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal {
        // TODO is vBase.truncate() is necessary? can it be passed from args?
        if (poolId != address(protocol.vBase).truncate()) {
            set.realizeFundingPayment(poolId, protocol);
            set.active.include(poolId);
        }
        VTokenPosition.Position storage _VTokenPosition = set.positions[poolId];
        _VTokenPosition.balance += balanceAdjustments.vTokenIncrease;
        _VTokenPosition.netTraderPosition += balanceAdjustments.traderPositionIncrease;

        VTokenPosition.Position storage _VBasePosition = set.positions[address(protocol.vBase).truncate()]; // TODO take vBaseTruncate from above
        _VBasePosition.balance += balanceAdjustments.vBaseIncrease;

        if (_VTokenPosition.balance == 0 && _VTokenPosition.liquidityPositions.active[0] == 0) {
            set.deactivate(poolId);
        }
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    function realizeFundingPayment(
        Set storage set,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal {
        set.realizeFundingPayment(poolId, protocol.pools[poolId].vPoolWrapper, protocol);
    }

    /// @notice realizes funding payment to base balance
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    function realizeFundingPayment(
        Set storage set,
        uint32 poolId,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal {
        // TODO change name _VTokenPosition to position
        VTokenPosition.Position storage _VTokenPosition = set.positions[poolId];
        int256 extrapolatedSumAX128 = wrapper.getSumAX128();

        VTokenPosition.Position storage _VBasePosition = set.positions[address(protocol.vBase).truncate()]; // TODO take vBaseTruncate from above
        int256 fundingPayment = _VTokenPosition.unrealizedFundingPayment(wrapper);
        _VBasePosition.balance += fundingPayment;

        _VTokenPosition.sumAX128Ckpt = extrapolatedSumAX128;

        emit Account.FundingPayment(set.accountNo, poolId, 0, 0, fundingPayment);
    }

    /// @notice get or create token position
    /// @dev activates inactive vToken if isCreateNew is true else reverts
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param createNew if 'vToken' is inactive then activates (true) else reverts with TokenInactive(false)
    /// @param protocol platform constants
    /// @return position - VTokenPosition corresponding to 'vToken'
    function getTokenPosition(
        Set storage set,
        uint32 poolId,
        bool createNew,
        Account.ProtocolInfo storage protocol
    ) internal returns (VTokenPosition.Position storage position) {
        // TODO is vBase.truncate() is necessary? can it be passed from args?
        if (poolId != address(protocol.vBase).truncate()) {
            if (createNew) {
                set.activate(poolId);
            } else if (!set.active.exists(poolId)) {
                revert TokenInactive(poolId);
            }
        }

        position = set.positions[poolId];
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param swapParams parameters for swap
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return set.swapToken(poolId, swapParams, poolId.vPoolWrapper(protocol), protocol);
    }

    /// @notice swaps tokens (Long and Short) with input in token amount
    /// @dev activates inactive vToe
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param vTokenAmount amount of the token
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapTokenAmount(
        Set storage set,
        uint32 poolId,
        int256 vTokenAmount,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return
            set.swapToken(
                poolId,
                /// @dev 0 means no price limit and false means amount mentioned is token amount
                IClearingHouseStructures.SwapParams(vTokenAmount, 0, false, false),
                poolId.vPoolWrapper(protocol),
                protocol
            );
    }

    /// @notice swaps tokens (Long and Short) with input in token amount / base amount
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param swapParams parameters for swap
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    /// @return vTokenAmountOut - token amount coming out of pool
    /// @return vBaseAmountOut - base amount coming out of pool
    function swapToken(
        Set storage set,
        uint32 poolId,
        IClearingHouseStructures.SwapParams memory swapParams,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        (vTokenAmountOut, vBaseAmountOut) = wrapper.swapToken(
            swapParams.amount,
            swapParams.sqrtPriceLimit,
            swapParams.isNotional
        );

        // change direction basis uniswap to balance increase
        vTokenAmountOut = -vTokenAmountOut;
        vBaseAmountOut = -vBaseAmountOut;

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments = IClearingHouseStructures
            .BalanceAdjustments(vBaseAmountOut, vTokenAmountOut, vTokenAmountOut);

        set.update(balanceAdjustments, poolId, protocol);

        emit Account.TokenPositionChange(set.accountNo, poolId, vTokenAmountOut, vBaseAmountOut);
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param protocol platform constants
    function removeLimitOrder(
        Set storage set,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        Account.ProtocolInfo storage protocol
    ) internal {
        set.removeLimitOrder(poolId, tickLower, tickUpper, protocol.pools[poolId].vPoolWrapper, protocol);
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        return set.liquidityChange(poolId, liquidityChangeParams, protocol.pools[poolId].vPoolWrapper, protocol);
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        return set.liquidateLiquidityPositions(poolId, protocol.pools[poolId].vPoolWrapper, protocol);
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(Set storage set, Account.ProtocolInfo storage protocol)
        internal
        returns (int256 notionalAmountClosed)
    {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(set.active[i], protocol);
        }
    }

    /// @notice function to liquidate liquidity positions for a particular token
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        uint32 poolId,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        set.getTokenPosition(poolId, false, protocol).liquidityPositions.closeAllLiquidityPositions(
            set.accountNo,
            poolId,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, poolId, protocol);

        return getNotionalValue(poolId, balanceAdjustments.vTokenIncrease, balanceAdjustments.vBaseIncrease, protocol);
    }

    /// @notice function to liquidate all liquidity positions
    /// @param set VTokenPositionSet
    /// @param protocol platform constants
    /// @return notionalAmountClosed - value of tokens coming out (in base) of all the ranges closed
    function liquidateLiquidityPositions(
        Set storage set,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 notionalAmountClosed) {
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];
            if (truncated == 0) break;

            notionalAmountClosed += set.liquidateLiquidityPositions(set.active[i], wrapper, protocol);
        }
    }

    /// @notice function for liquidity add/remove
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param liquidityChangeParams includes tickLower, tickUpper, liquidityDelta, limitOrderType
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @return vTokenAmountOut amount of tokens that account received (positive) or paid (negative)
    /// @return vBaseAmountOut amount of base tokens that account received (positive) or paid (negative)
    function liquidityChange(
        Set storage set,
        uint32 poolId,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(poolId, true, protocol);

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        vTokenPosition.liquidityPositions.liquidityChange(
            set.accountNo,
            poolId,
            liquidityChangeParams,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, poolId, protocol);

        if (liquidityChangeParams.closeTokenPosition) {
            set.swapTokenAmount(poolId, -balanceAdjustments.traderPositionIncrease, protocol);
        }

        return (balanceAdjustments.vTokenIncrease, balanceAdjustments.vBaseIncrease);
    }

    /// @notice function to remove an eligible limit order
    /// @dev checks whether the current price is on the correct side of the range based on the type of limit order (None, Low, High)
    /// @param set VTokenPositionSet
    /// @param poolId id of the rage trade pool
    /// @param tickLower lower tick index for the range
    /// @param tickUpper upper tick index for the range
    /// @param wrapper VPoolWrapper to override the set wrapper
    /// @param protocol platform constants
    function removeLimitOrder(
        Set storage set,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        IVPoolWrapper wrapper,
        Account.ProtocolInfo storage protocol
    ) internal {
        VTokenPosition.Position storage vTokenPosition = set.getTokenPosition(poolId, false, protocol);

        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;
        int24 currentTick = poolId.getVirtualCurrentTick(protocol);

        vTokenPosition.liquidityPositions.removeLimitOrder(
            set.accountNo,
            poolId,
            currentTick,
            tickLower,
            tickUpper,
            wrapper,
            balanceAdjustments
        );

        set.update(balanceAdjustments, poolId, protocol);
    }

    function getInfo(Set storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256 vBaseBalance, IClearingHouseStructures.VTokenPositionView[] memory vTokenPositions)
    {
        vBaseBalance = set.positions[address(protocol.vBase).truncate()].balance; // TODO can be optimized?

        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        vTokenPositions = new IClearingHouseStructures.VTokenPositionView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            vTokenPositions[i].vTokenAddress = address(protocol.pools[set.active[i]].vToken);
            vTokenPositions[i].balance = set.positions[set.active[i]].balance;
            vTokenPositions[i].netTraderPosition = set.positions[set.active[i]].netTraderPosition;
            vTokenPositions[i].sumAX128Ckpt = set.positions[set.active[i]].sumAX128Ckpt;
            vTokenPositions[i].liquidityPositions = set.positions[set.active[i]].liquidityPositions.getInfo();
        }
    }

    function getNetPosition(
        Set storage set,
        uint32 poolId,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 netPosition) {
        if (!set.active.exists(poolId)) return 0;
        VTokenPosition.Position storage tokenPosition = set.positions[poolId];
        return tokenPosition.getNetPosition(poolId, protocol);
    }
}
