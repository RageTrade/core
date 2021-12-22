//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ClearingHouse } from '../ClearingHouse.sol';
import { Account, VTokenPosition, VTokenPositionSet, LimitOrderType, LiquidityPositionSet, LiquidityPosition } from '../libraries/Account.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

contract ClearingHouseTest is ClearingHouse {
    using Account for Account.Info;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;

    constructor(
        address VPoolFactory,
        address _realBase,
        address _insuranceFundAddress
    ) ClearingHouse(VPoolFactory, _realBase, _insuranceFundAddress) {}

    // TODO remove
    function getTruncatedTokenAddress(VTokenAddress vTokenAddress) external pure returns (uint32) {
        return vTokenAddress.truncate();
    }

    function cleanPositions(uint256 accountNo) external {
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        Account.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[uint32(uint160(constants.VBASE_ADDRESS))];
        balanceAdjustments = Account.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(balanceAdjustments, VTokenAddress.wrap(constants.VBASE_ADDRESS), constants);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            tokenPosition = set.positions[truncatedAddress];
            balanceAdjustments = Account.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(balanceAdjustments, vTokenAddresses[truncatedAddress], constants);
        }
    }

    function getTokenAddressInVTokenAddresses(VTokenAddress vTokenAddress)
        external
        view
        returns (VTokenAddress vTokenAddressInVTokenAddresses)
    {
        return vTokenAddresses[vTokenAddress.truncate()];
    }

    function getAccountOwner(uint256 accountNo) external view returns (address owner) {
        return accounts[accountNo].owner;
    }

    function getAccountNumInTokenPositionSet(uint256 accountNo) external view returns (uint256 accountNoInTokenSet) {
        return accounts[accountNo].tokenPositions.accountNo;
    }

    function getAccountDepositBalance(uint256 accountNo, VTokenAddress vTokenAddress)
        external
        view
        returns (uint256 balance)
    {
        balance = accounts[accountNo].tokenDeposits.deposits[vTokenAddress.truncate()];
    }

    function getAccountOpenTokenPosition(uint256 accountNo, VTokenAddress vTokenAddress)
        external
        view
        returns (int256 balance, int256 netTraderPosition)
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            vTokenAddress.truncate()
        ];
        balance = vTokenPosition.balance;
        netTraderPosition = vTokenPosition.netTraderPosition;
    }

    function getAccountLiquidityPositionNum(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (uint8 num)
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[VTokenAddress.wrap(vTokenAddress).truncate()]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
    }

    function getAccountLiquidityPositionDetails(
        uint256 accountNo,
        address vTokenAddress,
        uint8 num // TODO change to fetch by ticks
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            LimitOrderType limitOrderType,
            uint128 liquidity,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[VTokenAddress.wrap(vTokenAddress).truncate()]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        return (
            liquidityPosition.tickLower,
            liquidityPosition.tickUpper,
            liquidityPosition.limitOrderType,
            liquidityPosition.liquidity,
            liquidityPosition.sumALastX128,
            liquidityPosition.sumBInsideLastX128,
            liquidityPosition.sumFpInsideLastX128,
            liquidityPosition.sumFeeInsideLastX128
        );
    }

    function getAccountValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        return
            accounts[accountNo].getAccountValueAndRequiredMargin(
                isInitialMargin,
                vTokenAddresses,
                liquidationParams.minRequiredMargin,
                constants
            );
    }
}
