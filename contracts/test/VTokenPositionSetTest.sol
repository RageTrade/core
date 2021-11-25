//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition, LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { Constants } from '../utils/Constants.sol';

contract VTokenPositionSetTest {
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using Uint32L8ArrayLib for uint32[8];
    mapping(uint32 => address) vTokenAddresses;
    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(address vTokenAddress) external {
        VTokenPositionSet.activate(dummy, vTokenAddress);
        vTokenAddresses[VTokenPositionSet.truncate(vTokenAddress)] = vTokenAddress;
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(
        Account.BalanceAdjustments memory balanceAdjustments,
        address vTokenAddress,
        Constants memory constants
    ) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, vTokenAddress, constants);
    }

    // function getAllTokenPositionValueAndMargin(bool isInitialMargin, Constants memory constants)
    //     external
    //     view
    //     returns (int256, int256)
    // {
    //     return VTokenPositionSet.getAllTokenPositionValueAndMargin(dummy, isInitialMargin, vTokenAddresses, constants);
    // }

    function realizeFundingPaymentToAccount(address vTokenAddress, Constants memory constants) external {
        VTokenPositionSet.realizeFundingPayment(dummy, vTokenAddress, wrapper, constants);
    }

    // function getTokenPosition(address vTokenAddress) external {
    //     dummy.getTokenPosition(vTokenAddress);
    // }

    function swapTokenAmount(
        address vTokenAddress,
        int256 vTokenAmount,
        Constants memory constants
    ) external {
        dummy.swapTokenAmount(vTokenAddress, vTokenAmount, wrapper, constants);
    }

    function swapTokenNotional(
        address vTokenAddress,
        int256 vTokenNotional,
        Constants memory constants
    ) external {
        dummy.swapTokenNotional(vTokenAddress, vTokenNotional, wrapper, constants);
    }

    function liquidityChange1(address vTokenAddress, Constants memory constants) external {
        dummy.closeLiquidityPosition(
            vTokenAddress,
            dummy.getTokenPosition(vTokenAddress, constants).liquidityPositions.activate(-100, 100),
            wrapper,
            constants
        );
    }

    function liquidityChange2(
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        Constants memory constants
    ) external {
        LiquidityChangeParams memory liquidityChangeParams = LiquidityChangeParams(
            tickLower,
            tickUpper,
            liquidity,
            LimitOrderType.NONE
        );
        dummy.liquidityChange(vTokenAddress, liquidityChangeParams, wrapper, constants);
    }

    function liquidateLiquidityPositions(address vTokenAddress, Constants memory constants) external {
        dummy.liquidateLiquidityPositions(vTokenAddress, wrapper, constants);
    }

    function liquidateTokenPosition(
        address vTokenAddress,
        uint16 liquidationFeeFraction,
        uint256 liquidationMinSizeBaseAmount,
        uint8 targetMarginRation,
        uint256 fixFee,
        Constants memory constants
    ) external {
        LiquidationParams memory liquidationParams = LiquidationParams(
            liquidationFeeFraction,
            liquidationMinSizeBaseAmount,
            targetMarginRation,
            fixFee
        );
        dummy.getTokenPositionToLiquidate(vTokenAddress, liquidationParams, vTokenAddresses, constants);
    }

    function getIsActive(address vTokenAddress) external view returns (bool) {
        return dummy.active.exists(uint32(uint160(vTokenAddress)));
    }

    function getPositionDetails(address vTokenAddress)
        external
        view
        returns (
            int256 balance,
            int256 sumACkhpt,
            int256 netTraderPosition
        )
    {
        VTokenPosition.Position storage pos = dummy.positions[VTokenPositionSet.truncate(vTokenAddress)];
        return (pos.balance, pos.sumAChkpt, pos.netTraderPosition);
    }

    function abs(int256 x) external pure returns (int256) {
        return VTokenPositionSet.abs(x);
    }
}
