//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';

import { ClearingHouse } from '../protocol/clearinghouse/ClearingHouse.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouseTest is ClearingHouse {
    using Account for Account.UserInfo;
    using VTokenLib for VTokenAddress;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using LiquidityPosition for LiquidityPosition.Info;
    using SignedFullMath for int256;
    using DepositTokenSet for DepositTokenSet.Info;

    uint256 public fixFee;

    function setFixFee(uint256 _fixFee) external {
        fixFee = _fixFee;
    }

    function getFixFee(uint256) public view override returns (uint256) {
        return fixFee;
    }

    // TODO remove
    function getTruncatedTokenAddress(VTokenAddress vTokenAddress) external pure returns (uint32) {
        return vTokenAddress.truncate();
    }

    function cleanPositions(uint256 accountNo) external {
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        Account.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[VTokenAddress.wrap(address(protocol.vBase)).truncate()];
        balanceAdjustments = Account.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(balanceAdjustments, VTokenAddress.wrap(address(protocol.vBase)), protocol);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            tokenPosition = set.positions[truncatedAddress];
            balanceAdjustments = Account.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(balanceAdjustments, protocol.vTokenAddresses[truncatedAddress], protocol);
        }
    }

    function cleanDeposits(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(protocol.vTokenAddresses, protocol);
        DepositTokenSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            deposit = set.deposits[truncatedAddress];
            set.decreaseBalance(protocol.rTokens[truncatedAddress].tokenAddress, deposit);
        }
    }

    function getTokenAddressInVTokenAddresses(VTokenAddress vTokenAddress)
        external
        view
        returns (VTokenAddress vTokenAddressInVTokenAddresses)
    {
        return protocol.vTokenAddresses[vTokenAddress.truncate()];
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

    function getAccountTokenPositionFunding(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (int256 fundingPayment)
    {
        VTokenAddress vToken = VTokenAddress.wrap(vTokenAddress);
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            vToken.truncate()
        ];

        IVPoolWrapper wrapper = vToken.vPoolWrapper(protocol);

        fundingPayment = vTokenPosition.unrealizedFundingPayment(wrapper);
    }

    function getAccountLiquidityPositionFundingAndFee(
        uint256 accountNo,
        address vTokenAddress,
        uint8 num
    ) external view returns (int256 fundingPayment, uint256 unrealizedLiquidityFee) {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[VTokenAddress.wrap(vTokenAddress).truncate()]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = VTokenAddress
            .wrap(vTokenAddress)
            .vPoolWrapper(protocol)
            .getExtrapolatedValuesInside(liquidityPosition.tickLower, liquidityPosition.tickUpper);

        fundingPayment = liquidityPosition.unrealizedFundingPayment(
            wrapperValuesInside.sumAX128,
            wrapperValuesInside.sumFpInsideX128
        );

        unrealizedLiquidityFee = liquidityPosition.unrealizedFees(wrapperValuesInside.sumFeeInsideX128);
    }

    function getAccountLiquidityPositionDetails(
        uint256 accountNo,
        address vTokenAddress,
        uint8 num
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            LiquidityPosition.LimitOrderType limitOrderType,
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
        return accounts[accountNo].getAccountValueAndRequiredMargin(isInitialMargin, protocol);
    }
}
