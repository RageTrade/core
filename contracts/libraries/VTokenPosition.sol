//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { Account } from './Account.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { FundingPayment } from './FundingPayment.sol';
import { Protocol } from './Protocol.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { console } from 'hardhat/console.sol';

library VTokenPosition {
    using FullMath for uint256;
    using SignedFullMath for int256;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    using LiquidityPosition for LiquidityPosition.Info;
    using LiquidityPositionSet for LiquidityPosition.Set;
    using Protocol for Protocol.Info;

    enum RISK_SIDE {
        LONG,
        SHORT
    }

    /// @notice stores info for VTokenPositionSet
    /// @param active list of all active token truncated addresses
    /// @param positions mapping from truncated token addresses to VTokenPosition struct for that address
    struct Set {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => VTokenPosition.Info) positions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    struct Info {
        int256 balance; // vTokenLong - vTokenShort
        int256 netTraderPosition;
        int256 sumAX128Ckpt; // later look into cint64
        // this is moved from accounts to here because of the in margin available check
        // the loop needs to be done over liquidity positions of same token only
        LiquidityPosition.Set liquidityPositions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error AlreadyInitialized();

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param priceX128 price in fixed point 128
    /// @param wrapper pool wrapper corresponding to position
    function marketValue(
        VTokenPosition.Info storage position,
        uint256 priceX128,
        IVPoolWrapper wrapper
    ) internal view returns (int256 value) {
        value = position.balance.mulDiv(priceX128, FixedPoint128.Q128);
        value += unrealizedFundingPayment(position, wrapper);
    }

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param priceX128 price in fixed point 128
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    function marketValue(
        VTokenPosition.Info storage position,
        uint32 poolId,
        uint256 priceX128,
        Protocol.Info storage protocol
    ) internal view returns (int256 value) {
        return marketValue(position, priceX128, protocol.vPoolWrapperFor(poolId));
    }

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    function marketValue(
        VTokenPosition.Info storage position,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256) {
        uint256 priceX128 = protocol.getVirtualTwapPriceX128For(poolId);
        return marketValue(position, poolId, priceX128, protocol);
    }

    function riskSide(VTokenPosition.Info storage position) internal view returns (RISK_SIDE) {
        return position.balance > 0 ? RISK_SIDE.LONG : RISK_SIDE.SHORT;
    }

    /// @notice returns the unrealized funding payment for the trader position
    /// @param position token position
    /// @param wrapper pool wrapper corresponding to position
    function unrealizedFundingPayment(VTokenPosition.Info storage position, IVPoolWrapper wrapper)
        internal
        view
        returns (int256)
    {
        int256 extrapolatedSumAX128 = wrapper.getExtrapolatedSumAX128();
        int256 unrealizedFpBill = -FundingPayment.bill(
            extrapolatedSumAX128,
            position.sumAX128Ckpt,
            position.netTraderPosition
        );
        return unrealizedFpBill;
    }

    /// @notice returns the unrealized funding payment for the position
    /// @param position token position
    /// @param poolId id of the rage trade pool
    /// @param protocol platform constants
    function unrealizedFundingPayment(
        VTokenPosition.Info storage position,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256) {
        return unrealizedFundingPayment(position, protocol.vPoolWrapperFor(poolId));
    }

    function getNetPosition(
        VTokenPosition.Info storage position,
        uint32 poolId,
        Protocol.Info storage protocol
    ) internal view returns (int256) {
        return
            position.netTraderPosition +
            position.liquidityPositions.getNetPosition(protocol.vPoolFor(poolId).sqrtPriceCurrent());
    }
}
