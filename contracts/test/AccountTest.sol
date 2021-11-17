//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { Account, LiquidationParams } from '../libraries/Account.sol';
import { VTokenPositionSet, LiquidityChangeParams } from '../libraries/VTokenPositionSet.sol';
import { VTokenPosition } from '../libraries/VTokenPosition.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';
import { LimitOrderType } from '../libraries/LiquidityPosition.sol';
import { Constants } from '../Constants.sol';

contract AccountTest {
    using Account for Account.Info;
    using VTokenPosition for VTokenPosition.Position;

    Account.Info testAccount;
    mapping(uint32 => address) testVTokenAddresses;
    VPoolWrapperMock public wrapper;

    constructor() {
        wrapper = new VPoolWrapperMock();
        wrapper.setLiquidityRates(-100, 100, 4000, 1);
    }

    function truncate(address vTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(vTokenAddress));
    }

    function initToken(address vTokenAddress) external {
        testVTokenAddresses[truncate(vTokenAddress)] = vTokenAddress;
    }

    function addMargin(
        address vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        testAccount.addMargin(vTokenAddress, amount, constants);
    }

    function removeMargin(
        address vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) external {
        testAccount.removeMargin(vTokenAddress, amount, testVTokenAddresses, constants);
    }

    function removeProfit(uint256 amount, Constants memory constants) external {
        testAccount.removeProfit(amount, testVTokenAddresses, constants);
    }

    function swapTokenAmount(
        address vTokenAddress,
        int256 amount,
        Constants memory constants
    ) external {
        testAccount.swapTokenAmount(vTokenAddress, amount, testVTokenAddresses, wrapper, constants);
    }

    function swapTokenNotional(
        address vTokenAddress,
        int256 amount,
        Constants memory constants
    ) external {
        testAccount.swapTokenNotional(vTokenAddress, amount, testVTokenAddresses, wrapper, constants);
    }

    function liquidityChange(
        address vTokenAddress,
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
            limitOrderType
        );

        testAccount.liquidityChange(vTokenAddress, liquidityChangeParams, testVTokenAddresses, wrapper, constants);
    }

    function liquidateLiquidityPositions(uint16 liquidationFeeFraction, Constants memory constants) external {
        testAccount.liquidateLiquidityPositions(liquidationFeeFraction, testVTokenAddresses, wrapper, constants);
    }

    function liquidateTokenPosition(
        address vTokenAddress,
        uint16 liquidationFeeFraction,
        uint256 liquidationMinSizeBaseAmount,
        uint8 targetMarginRation,
        uint256 fixFee,
        Constants memory constants
    ) external {
        LiquidationParams memory liquidationParams = LiquidationParams(
            liquidationFeeFraction,
            liquidationMinSizeBaseAmount,
            targetMarginRation,
            fixFee
        );
        testAccount.liquidateTokenPosition(vTokenAddress, liquidationParams, testVTokenAddresses, constants);
    }

    function removeLimitOrder(
        address vTokenAddress,
        int24 tickLower,
        int24 tickUpper,
        int24 currentTick,
        Constants memory constants
    ) external {
        testAccount.removeLimitOrder(vTokenAddress, tickLower, tickUpper, currentTick, wrapper, constants);
    }

    function getAccountDepositBalance(address vTokenAddress) external view returns (uint256) {
        return testAccount.tokenDeposits.deposits[truncate(vTokenAddress)];
    }

    function getAccountTokenDetails(address vTokenAddress)
        external
        view
        returns (
            int256,
            int256,
            int256
        )
    {
        VTokenPosition.Position storage vTokenPosition = testAccount.tokenPositions.positions[truncate(vTokenAddress)];
        return (vTokenPosition.balance, vTokenPosition.netTraderPosition, vTokenPosition.sumAChkpt);
    }
}
