//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { Account } from '../libraries/Account.sol';

import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

contract VTokenPositionSetTest is AccountProtocolInfoMock {
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using AddressHelper for address;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using Uint32L8ArrayLib for uint32[8];

    mapping(uint32 => IVToken) vTokens;
    VTokenPositionSet.Set dummy;

    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
    }

    function init(IVToken vToken) external {
        VTokenPositionSet.activate(dummy, address(vToken).truncate());
        vTokens[address(vToken).truncate()] = vToken;
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
        wrapper.setLiquidityRates(-50, 50, 4000, 1);
    }

    function update(IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments, IVToken vToken) external {
        VTokenPositionSet.update(dummy, balanceAdjustments, address(vToken).truncate(), protocol);
    }

    function realizeFundingPaymentToAccount(IVToken vToken) external {
        VTokenPositionSet.realizeFundingPayment(dummy, address(vToken).truncate(), wrapper, protocol);
    }

    function swapTokenAmount(IVToken vToken, int256 vTokenAmount) external {
        dummy.swapToken(
            address(vToken).truncate(),
            IClearingHouseStructures.SwapParams(vTokenAmount, 0, false, false),
            wrapper,
            protocol
        );
    }

    function swapTokenNotional(IVToken vToken, int256 vTokenNotional) external {
        dummy.swapToken(
            address(vToken).truncate(),
            IClearingHouseStructures.SwapParams(vTokenNotional, 0, true, false),
            wrapper,
            protocol
        );
    }

    function liquidityChange(
        IVToken vToken,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external {
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams = IClearingHouseStructures
            .LiquidityChangeParams(
                tickLower,
                tickUpper,
                liquidity,
                0,
                0,
                false,
                IClearingHouseEnums.LimitOrderType.NONE
            );
        dummy.liquidityChange(address(vToken).truncate(), liquidityChangeParams, wrapper, protocol);
    }

    function liquidateLiquidityPositions(IVToken vToken) external {
        dummy.liquidateLiquidityPositions(address(vToken).truncate(), wrapper, protocol);
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
        VTokenPosition.Position storage pos = dummy.positions[address(vToken).truncate()];
        return (pos.balance, pos.sumAX128Ckpt, pos.netTraderPosition);
    }
}
