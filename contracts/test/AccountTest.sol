//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { Account, DepositTokenSet, LiquidationParams, SwapParams, VTokenAddress } from '../libraries/Account.sol';
import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { LiquidityPositionSet, LiquidityPosition } from '../libraries/LiquidityPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { Constants } from '../utils/Constants.sol';
import { RealTokenLib } from '../libraries/RealTokenLib.sol';
import { AccountStorage } from '../ClearingHouseStorage.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';

contract AccountTest {
    using Account for Account.Info;
    using VTokenPosition for VTokenPosition.Position;
    using VTokenPositionSet for VTokenPositionSet.Set;
    using LiquidityPositionSet for LiquidityPositionSet.Info;
    using DepositTokenSet for DepositTokenSet.Info;
    using VTokenLib for VTokenAddress;

    mapping(uint256 => Account.Info) accounts;
    AccountStorage public accountStorage;
    uint256 public fixFee;

    uint256 public numAccounts;

    constructor() {}

    function setAccountStorage(
        LiquidationParams calldata _liquidationParams,
        uint256 _minRequiredMargin,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _fixFee
    ) external {
        accountStorage.liquidationParams = _liquidationParams;
        accountStorage.minRequiredMargin = _minRequiredMargin;
        accountStorage.removeLimitOrderFee = _removeLimitOrderFee;
        accountStorage.minimumOrderNotional = _minimumOrderNotional;
        fixFee = _fixFee;
    }

    function registerPool(address full, IClearingHouse.RageTradePool calldata rageTradePool) external {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(accountStorage.vTokenAddresses[truncated].eq(address(0)));

        accountStorage.vTokenAddresses[truncated] = vTokenAddress;
        accountStorage.rtPools[vTokenAddress] = rageTradePool;
    }

    function setVBaseAddress(address VBASE_ADDRESS) external {
        accountStorage.VBASE_ADDRESS = VBASE_ADDRESS;
    }

    function createAccount() external {
        Account.Info storage newAccount = accounts[numAccounts];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = numAccounts;
        numAccounts++;
    }

    function cleanPositions(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(accountStorage.vTokenAddresses, accountStorage);
        VTokenPositionSet.Set storage set = accounts[accountNo].tokenPositions;
        VTokenPosition.Position storage tokenPosition;
        Account.BalanceAdjustments memory balanceAdjustments;

        tokenPosition = set.positions[uint32(uint160(accountStorage.VBASE_ADDRESS))];
        balanceAdjustments = Account.BalanceAdjustments(-tokenPosition.balance, 0, 0);
        set.update(balanceAdjustments, VTokenAddress.wrap(accountStorage.VBASE_ADDRESS), accountStorage);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            tokenPosition = set.positions[truncatedAddress];
            balanceAdjustments = Account.BalanceAdjustments(
                0,
                -tokenPosition.balance,
                -tokenPosition.netTraderPosition
            );
            set.update(balanceAdjustments, accountStorage.vTokenAddresses[truncatedAddress], accountStorage);
        }
    }

    function cleanDeposits(uint256 accountNo) external {
        accounts[accountNo].tokenPositions.liquidateLiquidityPositions(accountStorage.vTokenAddresses, accountStorage);
        DepositTokenSet.Info storage set = accounts[accountNo].tokenDeposits;
        uint256 deposit;

        deposit = set.deposits[uint32(uint160(accountStorage.VBASE_ADDRESS))];
        set.decreaseBalance(VTokenAddress.wrap(accountStorage.VBASE_ADDRESS), deposit, accountStorage);

        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncatedAddress = set.active[i];
            if (truncatedAddress == 0) break;
            deposit = set.deposits[truncatedAddress];
            set.decreaseBalance(accountStorage.vTokenAddresses[truncatedAddress], deposit, accountStorage);
        }
    }

    function truncate(address vTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(vTokenAddress));
    }

    function initToken(address vTokenAddress) external {
        accountStorage.vTokenAddresses[truncate(vTokenAddress)] = VTokenAddress.wrap(vTokenAddress);
    }

    function addMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount
    ) external {
        accounts[accountNo].addMargin(VTokenAddress.wrap(vTokenAddress), amount, accountStorage);
    }

    function removeMargin(
        uint256 accountNo,
        address vTokenAddress,
        uint256 amount
    ) external {
        accounts[accountNo].removeMargin(VTokenAddress.wrap(vTokenAddress), amount, accountStorage);
    }

    function removeProfit(uint256 accountNo, uint256 amount) external {
        accounts[accountNo].removeProfit(amount, accountStorage);
    }

    function swapTokenAmount(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            VTokenAddress.wrap(vTokenAddress),
            SwapParams(amount, 0, false, false),
            accountStorage
        );
    }

    function swapTokenNotional(
        uint256 accountNo,
        address vTokenAddress,
        int256 amount
    ) external {
        accounts[accountNo].swapToken(
            VTokenAddress.wrap(vTokenAddress),
            SwapParams(amount, 0, true, false),
            accountStorage
        );
    }

    function liquidityChange(
        uint256 accountNo,
        address vTokenAddress,
        LiquidityChangeParams memory liquidityChangeParams
    ) external {
        accounts[accountNo].liquidityChange(VTokenAddress.wrap(vTokenAddress), liquidityChangeParams, accountStorage);
    }

    function liquidateLiquidityPositions(uint256 accountNo)
        external
        returns (int256 keeperFee, int256 insuranceFundFee)
    {
        return accounts[accountNo].liquidateLiquidityPositions(fixFee, accountStorage);
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
        return Account.getLiquidationPriceX128AndFee(tokensToTrade, VTokenAddress.wrap(vTokenAddress), accountStorage);
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
            accountStorage
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
            accountStorage
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

    function getAccountValueAndRequiredMargin(uint256 accountNo, bool isInitialMargin)
        external
        view
        returns (int256 accountMarketValue, int256 requiredMargin)
    {
        (accountMarketValue, requiredMargin) = accounts[accountNo].getAccountValueAndRequiredMargin(
            isInitialMargin,
            accountStorage
        );
    }

    function getAccountProfit(uint256 accountNo) external view returns (int256 profit) {
        return accounts[accountNo].tokenPositions.getAccountMarketValue(accountStorage.vTokenAddresses, accountStorage);
    }
}
