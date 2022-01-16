//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { DepositTokenSet } from '../libraries/DepositTokenSet.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';
import { RTokenLib } from '../libraries/RTokenLib.sol';

import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVBase } from '../interfaces/IVBase.sol';

contract AccountTest {
    using Account for Account.UserInfo;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using DepositTokenSet for DepositTokenSet.Info;
    using VTokenLib for VTokenAddress;

    mapping(uint256 => Account.UserInfo) accounts;
    Account.ProtocolInfo public protocol;
    uint256 public fixFee;

    uint256 public numAccounts;

    constructor() {}

    function setAccountStorage(
        Account.LiquidationParams calldata _liquidationParams,
        uint256 _minRequiredMargin,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _fixFee
    ) external {
        protocol.liquidationParams = _liquidationParams;
        protocol.minRequiredMargin = _minRequiredMargin;
        protocol.removeLimitOrderFee = _removeLimitOrderFee;
        protocol.minimumOrderNotional = _minimumOrderNotional;
        fixFee = _fixFee;
    }

    function registerPool(address full, IClearingHouse.RageTradePool calldata rageTradePool) external {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(protocol.vTokenAddresses[truncated].eq(address(0)));

        protocol.vTokenAddresses[truncated] = vTokenAddress;
        protocol.pools[vTokenAddress] = rageTradePool;
    }

    function setVBaseAddress(IVBase _vBase) external {
        protocol.vBase = _vBase;
    }

    function createAccount() external {
        Account.UserInfo storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = numAccounts;
        numAccounts++;
    }

    function cleanPositions(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(protocol.vTokenAddresses, protocol);
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

    function truncate(address vTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(vTokenAddress));
    }

    function initToken(address vTokenAddress) external {
        protocol.vTokenAddresses[truncate(vTokenAddress)] = VTokenAddress.wrap(vTokenAddress);
    }

    function initCollateral(
        address rTokenAddress,
        address oracleAddress,
        uint32 twapDuration
    ) external {
        RTokenLib.RToken memory token = RTokenLib.RToken(rTokenAddress, oracleAddress, twapDuration);
        protocol.rTokens[truncate(token.tokenAddress)] = token;
    }

    function addMargin(
        uint256 accountNo,
        address realTokenAddress,
        uint256 amount
    ) external {
        accounts[accountNo].addMargin(realTokenAddress, amount);
    }

    function removeMargin(
        uint256 accountNo,
        address realTokenAddress,
        uint256 amount
    ) external {
        accounts[accountNo].removeMargin(realTokenAddress, amount, protocol);
    }

    function removeProfit(uint256 accountNo, uint256 amount) external {
        accounts[accountNo].removeProfit(amount, protocol);
    }

    function swapTokenAmount(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            VTokenAddress.wrap(vTokenAddress),
            VTokenPositionSet.SwapParams(amount, 0, false, false),
            protocol
        );
    }

    function swapTokenNotional(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            VTokenAddress.wrap(vTokenAddress),
            VTokenPositionSet.SwapParams(amount, 0, true, false),
            protocol
        );
    }

    function liquidityChange(
        uint256 accountNo,
        address vTokenAddress,
        LiquidityPositionSet.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        accounts[accountNo].liquidityChange(VTokenAddress.wrap(vTokenAddress), liquidityChangeParams, protocol);
    }

    function liquidateLiquidityPositions(uint256 accountNo)
        external
        returns (int256 keeperFee, int256 insuranceFundFee)
    {
        return accounts[accountNo].liquidateLiquidityPositions(fixFee, protocol);
    }

    function getLiquidationPriceX128AndFee(int256 tokensToTrade, address vTokenAddress)
        external
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        return Account.getLiquidationPriceX128AndFee(tokensToTrade, VTokenAddress.wrap(vTokenAddress), protocol);
    }

    function liquidateTokenPosition(
        uint256 accountNo,
        uint256 liquidatorAccountNo,
        address vTokenAddress
    ) external {
        accounts[accountNo].liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            10000,
            VTokenAddress.wrap(vTokenAddress),
            fixFee,
            protocol
        );
    }

    function removeLimitOrder(
        uint256 accountNo,
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 removeLimitOrderFee
    ) external {
        accounts[accountNo].removeLimitOrder(
            VTokenAddress.wrap(vTokenAddress),
            tickLower,
            tickUpper,
            removeLimitOrderFee,
            protocol
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

    function getAccountValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        (accountMarketValue, requiredMargin) = accounts[accountNo].getAccountValueAndRequiredMargin(
            isInitialMargin,
            protocol
        );
    }

    function getAccountProfit(uint256 accountNo) external view returns (int256 profit) {
        return accounts[accountNo].tokenPositions.getAccountMarketValue(protocol.vTokenAddresses, protocol);
    }
}
