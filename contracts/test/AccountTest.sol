//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { Account, DepositTokenSet, LiquidationParams, SwapParams, VTokenAddress } from '../libraries/Account.sol';
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
    mapping(uint32 => VTokenAddress) testVTokenAddresses;
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
            set.update(balanceAdjustments, testVTokenAddresses[truncatedAddress], constants);
        }
    }

    function cleanDeposits(uint256 accountNo, Constants memory constants) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(testVTokenAddresses, constants);
        DepositTokenSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        deposit = set.deposits[uint32(uint160(constants.VBASE_ADDRESS))];
        set.decreaseBalance(VTokenAddress.wrap(constants.VBASE_ADDRESS), deposit, constants);

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
        testVTokenAddresses[truncate(vTokenAddress)] = VTokenAddress.wrap(vTokenAddress);
    }

    function addMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        accounts[accountNo].addMargin(VTokenAddress.wrap(vTokenAddress), amount, constants);
    }

    function removeMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount,
        uint256 minRequiredMargin,
        Constants memory constants
    ) external {
        accounts[accountNo].removeMargin(
            VTokenAddress.wrap(vTokenAddress),
            amount,
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
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
            VTokenAddress.wrap(vTokenAddress),
            SwapParams(amount, 0, false, false),
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
            VTokenAddress.wrap(vTokenAddress),
            SwapParams(amount, 0, true, false),
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
            VTokenAddress.wrap(vTokenAddress),
            liquidityChangeParams,
            testVTokenAddresses,
            minRequiredMargin,
            constants
        );
    }

    function liquidateLiquidityPositions(
        uint256 accountNo,
        LiquidationParams memory liquidationParams,
        Constants memory constants
    ) external returns (int256 keeperFee, int256 insuranceFundFee) {
        return accounts[accountNo].liquidateLiquidityPositions(testVTokenAddresses, liquidationParams, constants);
    }

    function getLiquidationPriceX128AndFee(
        int256 tokensToTrade,
        address vTokenAddress,
        LiquidationParams memory liquidationParams,
        Constants memory constants
    )
        external
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        return
            Account.getLiquidationPriceX128AndFee(
                tokensToTrade,
                VTokenAddress.wrap(vTokenAddress),
                liquidationParams,
                constants
            );
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
            VTokenAddress.wrap(vTokenAddress),
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
        uint256 removeLimitOrderFee,
        Constants memory constants
    ) external {
        accounts[accountNo].removeLimitOrder(
            VTokenAddress.wrap(vTokenAddress),
            tickLower,
            tickUpper,
            removeLimitOrderFee,
            constants
        );
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
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumAX128Ckpt);
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
            liquidityPosition.sumALastX128,
            liquidityPosition.sumBInsideLastX128,
            liquidityPosition.sumFpInsideLastX128,
            liquidityPosition.sumFeeInsideLastX128
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
