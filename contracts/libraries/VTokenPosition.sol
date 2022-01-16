//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { Account } from './Account.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';
import { FundingPayment } from './FundingPayment.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

library VTokenPosition {
    using VTokenLib for VTokenAddress;
    using FullMath for uint256;
    using SignedFullMath for int256;
    using LiquidityPosition for LiquidityPosition.Info;

    enum RISK_SIDE {
        LONG,
        SHORT
    }

    struct Position {
        int256 balance; // vTokenLong - vTokenShort
        int256 netTraderPosition;
        int256 sumAX128Ckpt; // later look into cint64
        // this is moved from accounts to here because of the in margin available check
        // the loop needs to be done over liquidity positions of same token only
        LiquidityPositionSet.Info liquidityPositions;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    error AlreadyInitialized();

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param priceX128 price in fixed point 128
    /// @param wrapper pool wrapper corresponding to position
    function marketValue(
        Position storage position,
        uint256 priceX128,
        IVPoolWrapper wrapper
    ) internal view returns (int256 value) {
        //TODO: Remove logs
        // console.log('Token Position Balance:');
        // console.logInt(position.balance);
        // console.log('Token PriceX128:');
        // console.logInt(int256(priceX128));
        value = position.balance.mulDiv(priceX128, FixedPoint128.Q128);
        // console.log('Token Value:');
        // console.logInt(value);
        value += unrealizedFundingPayment(position, wrapper);
    }

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param priceX128 price in fixed point 128
    /// @param vToken tokenAddress corresponding to the position
    /// @param protocol platform constants
    function marketValue(
        Position storage position,
        VTokenAddress vToken,
        uint256 priceX128,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256 value) {
        return marketValue(position, priceX128, vToken.vPoolWrapper(protocol));
    }

    /// @notice returns the market value of the supplied token position
    /// @param position token position
    /// @param vToken tokenAddress corresponding to the position
    /// @param protocol platform constants
    function marketValue(
        Position storage position,
        VTokenAddress vToken,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256) {
        uint256 priceX128 = vToken.getVirtualTwapPriceX128(protocol);
        return marketValue(position, vToken, priceX128, protocol);
    }

    function riskSide(Position storage position) internal view returns (RISK_SIDE) {
        return position.balance > 0 ? RISK_SIDE.LONG : RISK_SIDE.SHORT;
    }

    /// @notice returns the unrealized funding payment for the trader position
    /// @param position token position
    /// @param wrapper pool wrapper corresponding to position
    function unrealizedFundingPayment(Position storage position, IVPoolWrapper wrapper) internal view returns (int256) {
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
    /// @param vToken tokenAddress corresponding to the position
    /// @param protocol platform constants
    function unrealizedFundingPayment(
        Position storage position,
        VTokenAddress vToken,
        Account.ProtocolInfo storage protocol
    ) internal view returns (int256) {
        return unrealizedFundingPayment(position, vToken.vPoolWrapper(protocol));
    }
}
