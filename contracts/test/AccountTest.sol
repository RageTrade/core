//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { Account, LiquidationParams, SwapParams } from '../libraries/Account.sol';
import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPositionSet, LiquidityPosition } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { Constants } from '../utils/Constants.sol';

contract AccountTest {
    using Account for Account.Info;
    using VTokenLib for VTokenAddress;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;

    Account.Info testAccount;
    Account.Info testLiquidatorAccount;
    mapping(uint32 => VTokenAddress) testVTokenAddresses;
    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
    }

    function cleanPositions(Constants memory constants) external {
        testAccount.tokenPositions.liquidateLiquidityPositions(testVTokenAddresses, wrapper, constants);
        VTokenPositionSet.Set storage set = testAccount.tokenPositions;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            testAccount.swapToken(
                testVTokenAddresses[truncatedAddress],
                SwapParams(-set.positions[truncatedAddress].balance, 0, false),
                testVTokenAddresses,
                wrapper,
                constants
            );
        }
    }

    function truncate(address vTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(vTokenAddress));
    }

    function initToken(VTokenAddress vTokenAddress) external {
        testVTokenAddresses[vTokenAddress.truncate()] = vTokenAddress;
    }

    function addMargin(
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        testAccount.addMargin(vTokenAddress, amount, constants);
    }

    function removeMargin(
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        testAccount.removeMargin(vTokenAddress, amount, testVTokenAddresses, constants);
    }

    function removeProfit(uint256 amount, Constants memory constants) external {
        testAccount.removeProfit(amount, testVTokenAddresses, constants);
    }

    function swapTokenAmount(
        VTokenAddress vTokenAddress,
        int256 amount,
        Constants memory constants
    ) external {
        testAccount.swapToken(vTokenAddress, SwapParams(amount, 0, false), testVTokenAddresses, wrapper, constants);
    }

    function swapTokenNotional(
        VTokenAddress vTokenAddress,
        int256 amount,
        Constants memory constants
    ) external {
        testAccount.swapToken(vTokenAddress, SwapParams(amount, 0, true), testVTokenAddresses, wrapper, constants);
    }

    function liquidityChange(
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity,
        LimitOrderType limitOrderType,
        Constants memory constants
    ) external {
        LiquidityChangeParams memory liquidityChangeParams = LiquidityChangeParams(
            tickLower,
            tickUpper,
            liquidity,
            0,
            0,
            false,
            limitOrderType
        );

        testAccount.liquidityChange(vTokenAddress, liquidityChangeParams, testVTokenAddresses, wrapper, constants);
    }

    function liquidateLiquidityPositions(
        uint256 fixFee,
        uint16 liquidationFeeFraction,
        uint16 insuranceFundFeeShareBps,
        Constants memory constants
    ) external {
        LiquidationParams memory liquidationParams = LiquidationParams(
            fixFee,
            liquidationFeeFraction,
            0,
            insuranceFundFeeShareBps
        );
        testAccount.liquidateLiquidityPositions(testVTokenAddresses, wrapper, liquidationParams, constants);
    }

    function liquidateTokenPosition(
        VTokenAddress vTokenAddress,
        uint256 fixFee,
        uint16 liquidationFeeFraction,
        uint16 tokenLiquidationPriceDeltaBps,
        uint16 insuranceFundFeeShareBps,
        Constants memory constants
    ) external {
        LiquidationParams memory liquidationParams = LiquidationParams(
            fixFee,
            liquidationFeeFraction,
            tokenLiquidationPriceDeltaBps,
            insuranceFundFeeShareBps
        );
        testAccount.liquidateTokenPosition(
            testLiquidatorAccount,
            10000,
            vTokenAddress,
            liquidationParams,
            testVTokenAddresses,
            constants
        );
    }

    function removeLimitOrder(
        VTokenAddress vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick,
        Constants memory constants
    ) external {
        testAccount.removeLimitOrder(vTokenAddress, tickLower, tickUpper, currentTick, 0, wrapper, constants);
    }

    function getAccountDepositBalance(address vTokenAddress) external view returns (uint256) {
        return testAccount.tokenDeposits.deposits[truncate(vTokenAddress)];
    }

    function getAccountTokenDetails(address vTokenAddress)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumACkpt
        )
    {
        VTokenPosition.Position storage vTokenPosition = testAccount.tokenPositions.positions[truncate(vTokenAddress)];
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumAChkpt);
    }

    function getAccountLiquidityPositionNum(address vTokenAddress) external view returns (uint8 num) {
        LiquidityPositionSet.Info storage liquidityPositionSet = testAccount
            .tokenPositions
            .positions[truncate(vTokenAddress)]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
    }

    function getAccountLiquidityPositionDetails(address vTokenAddress, uint8 num)
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            LimitOrderType limitOrderType,
            uint128 liquidity,
            int256 sumALast,
            int256 sumBInsideLast,
            int256 sumFpInsideLast,
            uint256 longsFeeGrowthInsideLast,
            uint256 shortsFeeGrowthInsideLast
        )
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = testAccount
            .tokenPositions
            .positions[truncate(vTokenAddress)]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        return (
            liquidityPosition.tickLower,
            liquidityPosition.tickUpper,
            liquidityPosition.limitOrderType,
            liquidityPosition.liquidity,
            liquidityPosition.sumALast,
            liquidityPosition.sumBInsideLast,
            liquidityPosition.sumFpInsideLast,
            liquidityPosition.longsFeeGrowthInsideLast,
            liquidityPosition.shortsFeeGrowthInsideLast
        );
    }
}
