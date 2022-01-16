//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenLib } from '../libraries/VTokenLib.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract VTokenPositionSetTest is AccountProtocolInfoMock {
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for IVToken;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using Uint32L8ArrayLib for uint32[8];

    mapping(uint32 => IVToken) vTokens;
    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(IVToken vToken) external {
        VTokenPositionSet.activate(dummy, vToken);
        vTokens[vToken.truncate()] = vToken;
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(IClearingHouse.BalanceAdjustments memory balanceAdjustments, IVToken vToken) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vToken, protocol);
    }

    function realizeFundingPaymentToAccount(IVToken vToken) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vToken, wrapper, protocol);
    }

    function swapTokenAmount(IVToken vToken, int256 vTokenAmount) external {
        dummy.swapToken(vToken, IClearingHouse.SwapParams(vTokenAmount, 0, false, false), wrapper, protocol);
    }

    function swapTokenNotional(IVToken vToken, int256 vTokenNotional) external {
        dummy.swapToken(vToken, IClearingHouse.SwapParams(vTokenNotional, 0, true, false), wrapper, protocol);
    }

    function liquidityChange(
        IVToken vToken,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external {
        IClearingHouse.LiquidityChangeParams memory liquidityChangeParams = IClearingHouse.LiquidityChangeParams(
            tickLower,
            tickUpper,
            liquidity,
            0,
            0,
            false,
            IClearingHouse.LimitOrderType.NONE
        );
        dummy.liquidityChange(vToken, liquidityChangeParams, wrapper, protocol);
    }

    function liquidateLiquidityPositions(IVToken vToken) external {
        dummy.liquidateLiquidityPositions(vToken, wrapper, protocol);
    }

    function getIsActive(address vToken) external view returns (bool) {
        return dummy.active.exists(uint32(uint160(vToken)));
    }

    function getPositionDetails(IVToken vToken)
        external
        view
        returns (
            int256 balance,
            int256 sumACkhpt,
            int256 netTraderPosition
        )
    {
        VTokenPosition.Position storage pos = dummy.positions[vToken.truncate()];
        return (pos.balance, pos.sumAX128Ckpt, pos.netTraderPosition);
    }
}
