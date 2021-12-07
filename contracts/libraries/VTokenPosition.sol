//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { FullMath } from './FullMath.sol';
import { FixedPoint128 } from './uniswap/FixedPoint128.sol';
import { Account } from './Account.sol';
import { LiquidityPositionSet } from './LiquidityPositionSet.sol';
import { LiquidityPosition } from './LiquidityPosition.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { Constants } from '../utils/Constants.sol';
import { console } from 'hardhat/console.sol';

library VTokenPosition {
    error AlreadyInitialized();
    using VTokenLib for VTokenAddress;
    using FullMath for uint256;
    using FullMath for int256;
    using LiquidityPosition for LiquidityPosition.Info;

    enum RISK_SIDE {
        LONG,
        SHORT
    }

    struct Position {
        int256 balance; // vTokenLong - vTokenShort
        int256 netTraderPosition;
        int256 sumAChkpt; // later look into cint64
        // this is moved from accounts to here because of the in margin available check
        // the loop needs to be done over liquidity positions of same token only
        LiquidityPositionSet.Info liquidityPositions;
    }

    function marketValue(
        Position storage position,
        uint256 price,
        IVPoolWrapper wrapper
    ) internal view returns (int256 value) {
        //TODO: Remove logs
        // console.log('Token Position Balance:');
        // console.logInt(position.balance);
        // console.log('Token PriceX128:');
        // console.logInt(int256(price));
        value = position.balance.mulDiv(price, FixedPoint128.Q128);
        // console.log('Token Value:');
        // console.logInt(value);
        value -= unrealizedFundingPayment(position, wrapper);
    }

    function marketValue(
        Position storage position,
        VTokenAddress vToken,
        uint256 price,
        Constants memory constants
    ) internal view returns (int256 value) {
        return marketValue(position, price, vToken.vPoolWrapper(constants));
    }

    function marketValue(
        Position storage position,
        VTokenAddress vToken,
        Constants memory constants
    ) internal view returns (int256) {
        uint256 price = vToken.getVirtualTwapPriceX128(constants);
        return marketValue(position, vToken, price, constants);
    }

    function riskSide(Position storage position) internal view returns (RISK_SIDE) {
        return position.balance > 0 ? RISK_SIDE.LONG : RISK_SIDE.SHORT;
    }

    function unrealizedFundingPayment(Position storage position, IVPoolWrapper wrapper) internal view returns (int256) {
        int256 extrapolatedSumA = wrapper.getSumAX128();
        int256 unrealizedFP = position.netTraderPosition * (extrapolatedSumA - position.sumAChkpt);
        return unrealizedFP;
    }

    function unrealizedFundingPayment(
        Position storage position,
        VTokenAddress vToken,
        Constants memory constants
    ) internal view returns (int256) {
        return unrealizedFundingPayment(position, vToken.vPoolWrapper(constants));
    }
}
