//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams, SwapParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { Constants } from '../utils/Constants.sol';

import { AccountStorage } from '../ClearingHouseStorage.sol';

contract VTokenPositionSetTest {
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using Uint32L8ArrayLib for uint32[8];

    mapping(uint32 => VTokenAddress) vTokenAddresses;
    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    AccountStorage accountStorage;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(VTokenAddress vTokenAddress) external {
        VTokenPositionSet.activate(dummy, vTokenAddress);
        vTokenAddresses[vTokenAddress.truncate()] = vTokenAddress;
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(
        Account.BalanceAdjustments memory balanceAdjustments,
        VTokenAddress vTokenAddress,
        Constants memory constants
    ) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress, accountStorage);
    }

    // function getAllTokenPositionValueAndMargin(bool isInitialMargin, Constants memory constants)
    //     external
    //     view
    //     returns (int256, int256)
    // {
    //     return VTokenPositionSet.getAllTokenPositionValueAndMargin(dummy, isInitialMargin, vTokenAddresses, constants);
    // }

    function realizeFundingPaymentToAccount(VTokenAddress vTokenAddress, Constants memory constants) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vTokenAddress, wrapper, accountStorage);
    }

    // function getTokenPosition(address vTokenAddress) external {
    //     dummy.getTokenPosition(vTokenAddress);
    // }

    function swapTokenAmount(
        VTokenAddress vTokenAddress,
        int256 vTokenAmount,
        Constants memory constants
    ) external {
        dummy.swapToken(vTokenAddress, SwapParams(vTokenAmount, 0, false, false), wrapper, accountStorage);
    }

    function swapTokenNotional(
        VTokenAddress vTokenAddress,
        int256 vTokenNotional,
        Constants memory constants
    ) external {
        dummy.swapToken(vTokenAddress, SwapParams(vTokenNotional, 0, true, false), wrapper, accountStorage);
    }

    function liquidityChange(
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        Constants memory constants
    ) external {
        LiquidityChangeParams memory liquidityChangeParams = LiquidityChangeParams(
            tickLower,
            tickUpper,
            liquidity,
            0,
            0,
            false,
            LimitOrderType.NONE
        );
        dummy.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper, accountStorage);
    }

    function liquidateLiquidityPositions(VTokenAddress vTokenAddress, Constants memory constants) external {
        dummy.liquidateLiquidityPositions(vTokenAddress, wrapper, accountStorage);
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
