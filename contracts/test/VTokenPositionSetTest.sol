//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VBASE_ADDRESS } from '../Constants.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';

import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract VTokenPositionSetTest {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using Uint32L8ArrayLib for uint32[8];

    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(address vTokenAddress) external {
        VTokenPositionSet.activate(dummy, VBASE_ADDRESS);
        VTokenPositionSet.activate(dummy, vTokenAddress);
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(Account.BalanceAdjustments memory balanceAdjustments, address vTokenAddress) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress);
    }

    function realizeFundingPaymentToAccount(address vTokenAddress) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vTokenAddress, wrapper);
    }

    // function getTokenPosition(address vTokenAddress) external {
    //     dummy.getTokenPosition(vTokenAddress);
    // }

    function swapTokenAmount(address vTokenAddress, int256 vTokenAmount) external {
        dummy.swapTokenAmount(vTokenAddress, vTokenAmount, wrapper);
    }

    function swapTokenNotional(address vTokenAddress, int256 vTokenNotional) external {
        dummy.swapTokenNotional(vTokenAddress, vTokenNotional, wrapper);
    }

    function liquidityChange1(address vTokenAddress, int128 liquidity) external {
        dummy.liquidityChange(vTokenAddress, dummy.getTokenPosition(vTokenAddress).liquidityPositions.activate(-100, 100), liquidity, wrapper);
    }

    function liquidityChange2(
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external {
        LiquidityChangeParams memory liquidityChangeParams = LiquidityChangeParams(
            tickLower,
            tickUpper,
            liquidity,
            LimitOrderType.NONE
        );
        dummy.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper);
    }

    function getIsActive(address vTokenAddress) external view returns (bool) {
        return dummy.active.exists(uint32(uint160(vTokenAddress)));
    }

    function getPositionDetails(address vTokenAddress)
        external
        view
        returns (
            int256,
            int256,
            int256
        )
    {
        VTokenPosition.Position storage pos = dummy.positions[VTokenPositionSet.truncate(vTokenAddress)];
        return (pos.balance, pos.sumAChkpt, pos.netTraderPosition);
    }

    function abs(int256 x) external pure returns (int256) {
        return VTokenPositionSet.abs(x);
    }
}
