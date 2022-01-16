//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

contract VTokenPositionSetTest is AccountProtocolInfoMock {
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using Uint32L8ArrayLib for uint32[8];

    mapping(uint32 => VTokenAddress) vTokenAddresses;
    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(VTokenAddress vTokenAddress) external {
        VTokenPositionSet.activate(dummy, vTokenAddress);
        vTokenAddresses[vTokenAddress.truncate()] = vTokenAddress;
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(Account.BalanceAdjustments memory balanceAdjustments, VTokenAddress vTokenAddress) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress, protocol);
    }

    // function getAllTokenPositionValueAndMargin(bool isInitialMargin, Constants memory constants)
    //     external
    //     view
    //     returns (int256, int256)
    // {
    //     return VTokenPositionSet.getAllTokenPositionValueAndMargin(dummy, isInitialMargin, vTokenAddresses, constants);
    // }

    function realizeFundingPaymentToAccount(VTokenAddress vTokenAddress) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vTokenAddress, wrapper, protocol);
    }

    // function getTokenPosition(address vTokenAddress) external {
    //     dummy.getTokenPosition(vTokenAddress);
    // }

    function swapTokenAmount(VTokenAddress vTokenAddress, int256 vTokenAmount) external {
        dummy.swapToken(vTokenAddress, VTokenPositionSet.SwapParams(vTokenAmount, 0, false, false), wrapper, protocol);
    }

    function swapTokenNotional(VTokenAddress vTokenAddress, int256 vTokenNotional) external {
        dummy.swapToken(vTokenAddress, VTokenPositionSet.SwapParams(vTokenNotional, 0, true, false), wrapper, protocol);
    }

    function liquidityChange(
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external {
        LiquidityPositionSet.LiquidityChangeParams memory liquidityChangeParams = LiquidityPositionSet
            .LiquidityChangeParams(tickLower, tickUpper, liquidity, 0, 0, false, LiquidityPosition.LimitOrderType.NONE);
        dummy.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper, protocol);
    }

    function liquidateLiquidityPositions(VTokenAddress vTokenAddress) external {
        dummy.liquidateLiquidityPositions(vTokenAddress, wrapper, protocol);
    }

    // function liquidateTokenPosition(
    //     VTokenAddress vTokenAddress,
    //     uint16 liquidationFeeFraction,
    //     uint256 liquidationMinSizeBaseAmount,
    //     uint8 targetMarginRation,
    //     uint256 fixFee,
    //     Constants memory constants
    // ) external {
    //     LiquidationParams memory liquidationParams = LiquidationParams(
    //         liquidationFeeFraction,
    //         liquidationMinSizeBaseAmount,
    //         targetMarginRation,
    //         fixFee
    //     );
    //     dummy.getTokenPositionToLiquidate(vTokenAddress, liquidationParams, vTokenAddresses, constants);
    // }

    function getIsActive(address vTokenAddress) external view returns (bool) {
        return dummy.active.exists(uint32(uint160(vTokenAddress)));
    }

    function getPositionDetails(VTokenAddress vTokenAddress)
        external
        view
        returns (
            int256 balance,
            int256 sumACkhpt,
            int256 netTraderPosition
        )
    {
        VTokenPosition.Position storage pos = dummy.positions[vTokenAddress.truncate()];
        return (pos.balance, pos.sumAX128Ckpt, pos.netTraderPosition);
    }
}
