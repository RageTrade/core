//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { Account, DepositTokenSet, LiquidationParams, SwapParams } from '../libraries/Account.sol';
import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPositionSet, LiquidityPosition } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { Constants } from '../utils/Constants.sol';

contract AccountTest {
    using Account for Account.Info;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using DepositTokenSet for DepositTokenSet.Info;

    mapping(uint256 => Account.Info) accounts;
    mapping(uint32 => address) testVTokenAddresses;
    uint256 public numAccounts;

    constructor() {}

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = numAccounts;
        numAccounts++;
    }

    function cleanPositions(uint256 accountNo, Constants memory constants) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(testVTokenAddresses, constants);
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        Account.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[uint32(uint160(constants.VBASE_ADDRESS))];
        balanceAdjustments = Account.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(balanceAdjustments, constants.VBASE_ADDRESS, constants);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            tokenPosition = set.positions[truncatedAddress];
            balanceAdjustments = Account.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(balanceAdjustments, testVTokenAddresses[truncatedAddress], constants);
        }
    }

    function cleanDeposits(uint256 accountNo, Constants memory constants) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(testVTokenAddresses, constants);
        DepositTokenSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        deposit = set.deposits[uint32(uint160(constants.VBASE_ADDRESS))];
        set.decreaseBalance(constants.VBASE_ADDRESS, deposit, constants);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            deposit = set.deposits[truncatedAddress];
            set.decreaseBalance(testVTokenAddresses[truncatedAddress], deposit, constants);
        }
    }

    function truncate(address vTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(vTokenAddress));
    }

    function initToken(address vTokenAddress) external {
        testVTokenAddresses[truncate(vTokenAddress)] = vTokenAddress;
    }

    function addMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        accounts[accountNo].addMargin(vTokenAddress, amount, constants);
    }

    function removeMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].removeMargin(vTokenAddress, amount, testVTokenAddresses, minRequiredMargin, constants);
    }

    function removeProfit(
        uint256 accountNo,
        uint256 amount,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].removeProfit(amount, testVTokenAddresses, minRequiredMargin, constants);
    }

    function swapTokenAmount(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].swapToken(
            vTokenAddress,
            SwapParams(amount, 0, false),
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
    }

    function swapTokenNotional(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].swapToken(
            vTokenAddress,
            SwapParams(amount, 0, true),
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
    }

    function liquidityChange(
        uint256 accountNo,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].liquidityChange(
            vTokenAddress,
            liquidityChangeParams,
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
    }

    function liquidateLiquidityPositions(
        uint256 accountNo,
        uint256 fixFee,
        uint256 minRequiredMargin,
        uint16 liquidationFeeFraction,
        uint16 insuranceFundFeeShareBps,
        Constants memory constants
    ) external {
        LiquidationParams memory liquidationParams = LiquidationParams(
            fixFee,
            minRequiredMargin,
            liquidationFeeFraction,
            0,
            insuranceFundFeeShareBps
        );
        accounts[accountNo].liquidateLiquidityPositions(
            testVTokenAddresses,
            liquidationParams,
            minRequiredMargin,
            constants
        );
    }

    function getLiquidationPriceX128(
        int256 tokenBalance,
        address vTokenAddress,
        uint256 fixFee,
        uint256 minRequiredMargin,
        uint16 liquidationFeeFraction,
        uint16 tokenLiquidationPriceDeltaBps,
        uint16 insuranceFundFeeShareBps,
        Constants memory constants
    ) external view returns (uint256 liquidationPriceX128, uint256 liquidatorPriceX128) {
        LiquidationParams memory liquidationParams = LiquidationParams(
            fixFee,
            minRequiredMargin,
            liquidationFeeFraction,
            tokenLiquidationPriceDeltaBps,
            insuranceFundFeeShareBps
        );
        return Account.getLiquidationPriceX128(tokenBalance, vTokenAddress, liquidationParams, constants);
    }

    function liquidateTokenPosition(
        uint256 accountNo,
        uint256 liquidatorAccountNo,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        Constants memory constants
    ) external {
        accounts[accountNo].liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            10000,
            vTokenAddress,
            liquidationParams,
            testVTokenAddresses,
            constants
        );
    }

    function removeLimitOrder(
        uint256 accountNo,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        Constants memory constants
    ) external {
        accounts[accountNo].removeLimitOrder(vTokenAddress, tickLower, tickUpper, 0, constants);
    }

    function getAccountDepositBalance(uint256 accountNo, address vTokenAddress) external view returns (uint256) {
        return accounts[accountNo].tokenDeposits.deposits[truncate(vTokenAddress)];
    }

    function getAccountTokenDetails(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumACkpt
        )
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[
            truncate(vTokenAddress)
        ];
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumAChkpt);
    }

    function getAccountLiquidityPositionNum(uint256 accountNo, address vTokenAddress)
        external
        view
        returns (uint8 num)
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[truncate(vTokenAddress)]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
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
            LimitOrderType limitOrderType,
            uint128 liquidity,
            int256 sumALast,
            int256 sumBInsideLast,
            int256 sumFpInsideLast,
            uint256 longsFeeGrowthInsideLast,
            uint256 shortsFeeGrowthInsideLast
        )
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
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

    function getAccountValueAndRequiredMargin(
        uint256 accountNo,
        bool isInitialMargin,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external view returns (int256 accountMarketValue, int256 requiredMargin) {
        (accountMarketValue, requiredMargin) = accounts[accountNo].getAccountValueAndRequiredMargin(
            isInitialMargin,
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
    }

    function getAccountProfit(uint256 accountNo, Constants memory constants) external view returns (int256 profit) {
        return accounts[accountNo].tokenPositions.getAccountMarketValue(testVTokenAddresses, constants);
    }
}
