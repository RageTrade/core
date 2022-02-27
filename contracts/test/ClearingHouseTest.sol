//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { CTokenDepositSet } from '../libraries/CTokenDepositSet.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { PoolIdHelper } from '../libraries/PoolIdHelper.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { ClearingHouse } from '../protocol/clearinghouse/ClearingHouse.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouseTest is ClearingHouse {
    using Account for Account.UserInfo;
    using AddressHelper for address;
    using CTokenDepositSet for CTokenDepositSet.Info;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using LiquidityPosition for LiquidityPosition.Info;
    using PoolIdHelper for uint32;
    using SignedFullMath for int256;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using VTokenPosition for VTokenPosition.Position;

    uint256 public fixFee;

    function setFixFee(uint256 _fixFee) external {
        fixFee = _fixFee;
    }

    function _getFixFee(uint256) internal view override returns (uint256) {
        return fixFee;
    }

    // TODO remove
    function getTruncatedTokenAddress(IVToken vToken) external pure returns (uint32) {
        return address(vToken).truncate();
    }

    function cleanPositions(uint256 accountNo) external {
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[address(protocol.vBase).truncate()];
        balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(balanceAdjustments, address(protocol.vBase).truncate(), protocol);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 poolId = set.active[i];
            if (poolId == 0) break;
            tokenPosition = set.positions[poolId];
            balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(balanceAdjustments, poolId, protocol);
        }
    }

    function cleanDeposits(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(protocol);
        CTokenDepositSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 collateralId = set.active[i];
            if (collateralId == 0) break;
            deposit = set.deposits[collateralId];
            set.decreaseBalance(collateralId, deposit);
        }
    }

    function getTokenAddressInVTokens(IVToken vToken) external view returns (IVToken vTokenInIVTokenes) {
        return protocol.pools[address(vToken).truncate()].vToken;
    }

    function getAccountOwner(uint256 accountNo) external view returns (address owner) {
        return accounts[accountNo].owner;
    }

    function getAccountNumInTokenPositionSet(uint256 accountNo) external view returns (uint256 accountNoInTokenSet) {
        return accounts[accountNo].tokenPositions.accountNo;
    }

    function getAccountDepositBalance(uint256 accountNo, IVToken vToken) external view returns (uint256 balance) {
        balance = accounts[accountNo].tokenDeposits.deposits[address(vToken).truncate()];
    }

    function getAccountOpenTokenPosition(uint256 accountNo, IVToken vToken)
        external
        view
        returns (int256 balance, int256 netTraderPosition)
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            address(vToken).truncate()
        ];
        balance = vTokenPosition.balance;
        netTraderPosition = vTokenPosition.netTraderPosition;
    }

    function getAccountLiquidityPositionNum(uint256 accountNo, address vToken) external view returns (uint8 num) {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[vToken.truncate()]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
    }

    function getAccountTokenPositionFunding(uint256 accountNo, IVToken vToken)
        external
        view
        returns (int256 fundingPayment)
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            address(vToken).truncate()
        ];

        IVPoolWrapper wrapper = address(vToken).truncate().vPoolWrapper(protocol);

        fundingPayment = vTokenPosition.unrealizedFundingPayment(wrapper);
    }

    function getAccountLiquidityPositionFundingAndFee(
        uint256 accountNo,
        address vToken,
        uint8 num
    ) external view returns (int256 fundingPayment, uint256 unrealizedLiquidityFee) {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[vToken.truncate()]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        IVPoolWrapper.WrapperValuesInside memory wrapperValuesInside = vToken
            .truncate()
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
        address vToken,
        uint8 num
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            IClearingHouseEnums.LimitOrderType limitOrderType,
            uint128 liquidity,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[vToken.truncate()]
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
