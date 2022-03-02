//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../libraries/Account.sol';
import { CTokenDepositSet } from '../libraries/CTokenDepositSet.sol';
import { VTokenPositionSet } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPositionSet } from '../libraries/LiquidityPositionSet.sol';
import { AddressHelper } from '../libraries/AddressHelper.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LiquidityPosition } from '../libraries/LiquidityPosition.sol';

import { IClearingHouseEnums } from '../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IVBase } from '../interfaces/IVBase.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract AccountTest {
    using Account for Account.UserInfo;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using CTokenDepositSet for CTokenDepositSet.Info;
    using AddressHelper for address;

    mapping(uint256 => Account.UserInfo) accounts;
    Account.ProtocolInfo public protocol;
    uint256 public fixFee;

    uint256 public numAccounts;

    constructor() {}

    function setAccountStorage(
        IClearingHouseStructures.LiquidationParams calldata liquidationParams,
        uint256 minRequiredMargin,
        uint256 removeLimitOrderFee,
        uint256 minimumOrderNotional,
        uint256 fixFee_,
        address cBase
    ) external {
        protocol.liquidationParams = liquidationParams;
        protocol.minRequiredMargin = minRequiredMargin;
        protocol.removeLimitOrderFee = removeLimitOrderFee;
        protocol.minimumOrderNotional = minimumOrderNotional;
        protocol.cBase = IERC20(cBase);
        fixFee = fixFee_;
    }

    function registerPool(IClearingHouseStructures.Pool calldata poolInfo) external {
        uint32 poolId = address(poolInfo.vToken).truncate();

        // pool will not be registered twice by the rage trade factory
        assert(address(protocol.pools[poolId].vToken).isZero());

        protocol.pools[poolId] = poolInfo;
    }

    function setVBaseAddress(IVBase _vBase) external {
        protocol.vBase = _vBase;
    }

    function createAccount() external {
        Account.UserInfo storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        // newAccount.tokenPositions.accountNo = numAccounts;
        numAccounts++;
    }

    function cleanPositions(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(accountNo, protocol);
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        IClearingHouseStructures.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[address(protocol.vBase).truncate()];
        balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(accountNo, balanceAdjustments, address(protocol.vBase).truncate(), protocol);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 poolId = set.active[i];
            if (poolId == 0) break;
            tokenPosition = set.positions[poolId];
            balanceAdjustments = IClearingHouseStructures.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(accountNo, balanceAdjustments, poolId, protocol);
        }
    }

    function cleanDeposits(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(accountNo, protocol);
        CTokenDepositSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 collateralId = set.active[i];
            if (collateralId == 0) break;
            deposit = set.deposits[collateralId];
            set.decreaseBalance(collateralId, deposit);
        }
    }

    function truncate(address vToken) internal pure returns (uint32) {
        return uint32(uint160(vToken));
    }

    function initToken(address vToken) external {
        protocol.pools[truncate(vToken)].vToken = IVToken(vToken);
    }

    function initCollateral(
        IERC20 cToken,
        IOracle oracle,
        uint32 twapDuration
    ) external {
        IClearingHouseStructures.Collateral memory collateral = IClearingHouseStructures.Collateral(
            cToken,
            IClearingHouseStructures.CollateralSettings(oracle, twapDuration, true)
        );
        protocol.collaterals[truncate(address(collateral.token))] = collateral;
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
        accounts[accountNo].removeMargin(realTokenAddress, amount, protocol, true);
    }

    function updateProfit(uint256 accountNo, int256 amount) external {
        accounts[accountNo].updateProfit(amount, protocol, true);
    }

    function swapTokenAmount(
        uint256 accountNo,
        address vToken,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            vToken.truncate(),
            IClearingHouseStructures.SwapParams(amount, 0, false, false),
            protocol,
            true
        );
    }

    function swapTokenNotional(
        uint256 accountNo,
        address vToken,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            vToken.truncate(),
            IClearingHouseStructures.SwapParams(amount, 0, true, false),
            protocol,
            true
        );
    }

    function liquidityChange(
        uint256 accountNo,
        address vToken,
        IClearingHouseStructures.LiquidityChangeParams memory liquidityChangeParams
    ) external {
        accounts[accountNo].liquidityChange(vToken.truncate(), liquidityChangeParams, protocol, true);
    }

    function liquidateLiquidityPositions(uint256 accountNo)
        external
        returns (int256 keeperFee, int256 insuranceFundFee)
    {
        return accounts[accountNo].liquidateLiquidityPositions(fixFee, protocol);
    }

    function getLiquidationPriceX128AndFee(int256 tokensToTrade, address vToken)
        external
        view
        returns (
            uint256 liquidationPriceX128,
            uint256 liquidatorPriceX128,
            int256 insuranceFundFee
        )
    {
        return Account._getLiquidationPriceX128AndFee(tokensToTrade, vToken.truncate(), protocol);
    }

    function liquidateTokenPosition(
        uint256 accountNo,
        uint256 liquidatorAccountNo,
        address vToken
    ) external {
        accounts[accountNo].liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            10000,
            vToken.truncate(),
            fixFee,
            protocol,
            true
        );
    }

    function removeLimitOrder(
        uint256 accountNo,
        address vToken,
        int24 tickLower,
        int24 tickUpper,
        uint256 removeLimitOrderFee
    ) external {
        accounts[accountNo].removeLimitOrder(vToken.truncate(), tickLower, tickUpper, removeLimitOrderFee, protocol);
    }

    function getAccountDepositBalance(uint256 accountNo, address vToken) external view returns (uint256) {
        return accounts[accountNo].tokenDeposits.deposits[truncate(vToken)];
    }

    function getAccountTokenDetails(uint256 accountNo, address vToken)
        external
        view
        returns (
            int256 balance,
            int256 netTraderPosition,
            int256 sumACkpt
        )
    {
        VTokenPosition.Position storage vTokenPosition = accounts[accountNo].tokenPositions.positions[truncate(vToken)];
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumAX128Ckpt);
    }

    function getAccountLiquidityPositionNum(uint256 accountNo, address vToken) external view returns (uint8 num) {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[truncate(vToken)]
            .liquidityPositions;

        for (num = 0; num < liquidityPositionSet.active.length; num++) {
            if (liquidityPositionSet.active[num] == 0) break;
        }
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
            int256 vTokenAmountIn,
            int256 sumALastX128,
            int256 sumBInsideLastX128,
            int256 sumFpInsideLastX128,
            uint256 sumFeeInsideLastX128
        )
    {
        LiquidityPositionSet.Info storage liquidityPositionSet = accounts[accountNo]
            .tokenPositions
            .positions[truncate(vToken)]
            .liquidityPositions;
        LiquidityPosition.Info storage liquidityPosition = liquidityPositionSet.positions[
            liquidityPositionSet.active[num]
        ];

        return (
            liquidityPosition.tickLower,
            liquidityPosition.tickUpper,
            liquidityPosition.limitOrderType,
            liquidityPosition.liquidity,
            liquidityPosition.vTokenAmountIn,
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
        return accounts[accountNo].tokenPositions.getAccountMarketValue(protocol);
    }
}
