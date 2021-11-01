//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint96 } from './uniswap/FixedPoint96.sol';

import { Account } from './Account.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { VToken, VTokenLib } from '../libraries/VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

library VTokenPosition {
    error AlreadyInitialized();
    using VTokenLib for VToken;
    using FullMath for uint256;
    using LiquidityPosition for LiquidityPosition.Info;

    enum RISK_SIDE {
        LONG,
        SHORT
    }

    struct Position {
        // SLOT 1
        VToken vToken;
        int256 balance; // vTokenLong - vTokenShort
        // SLOT 2
        int256 netTraderPosition;
        int256 sumAChkpt; // later look into cint64
        // this is moved from accounts to here because of the in margin available check
        // the loop needs to be done over liquidity positions of same token only
        LiquidityPositionSet.Info liquidityPositions;
    }

    function initialize(Position storage position, VToken _vToken) internal {
        if (isInitialized(position)) {
            revert AlreadyInitialized();
        }
        position.vToken = _vToken;
    }

    function isInitialized(Position storage position) internal view returns (bool) {
        return VToken.unwrap(position.vToken) != address(0);
    }

    function getTokenPositionValue(Position storage position, uint256 price) internal view returns (int256 value) {
        value = (position.balance * int256(price)) / int256(FixedPoint96.Q96);
        value -= unrealizedFundingPayment(position);
    }

    function getTokenPositionValue(Position storage position) internal view returns (int256) {
        uint256 price = position.vToken.getVirtualTwapPrice();
        return getTokenPositionValue(position, price);
    }

    function riskSide(Position storage position) internal view returns (RISK_SIDE) {
        return position.balance > 0 ? RISK_SIDE.LONG : RISK_SIDE.SHORT;
    }

    function unrealizedFundingPayment(Position storage position) internal view returns (int256) {
        int256 extrapolatedSumA = int256(position.vToken.vPoolWrapper().getExtrapolatedSumA());
        int256 unrealizedFP = position.netTraderPosition * (extrapolatedSumA - position.sumAChkpt);
        return unrealizedFP;
    }
}
