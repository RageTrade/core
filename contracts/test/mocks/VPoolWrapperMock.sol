//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapperMock is IVPoolWrapper {
    struct ValuesInside {
        int256 sumA;
        int256 sumBInside;
        int256 sumFpInside;
        uint256 longsFeeGrowthInside;
        uint256 shortsFeeGrowthInside;
    }

    mapping(int24 => mapping(int24 => ValuesInside)) public override getValuesInside;

    struct LiquidityRate {
        uint256 vBasePerLiquidity;
        uint256 vTokenPerLiquidity;
    }
    mapping(int24 => mapping(int24 => LiquidityRate)) internal _liquidityRates;

    uint16 public immutable override initialMarginRatio;
    uint16 public immutable override maintainanceMarginRatio;
    uint32 public immutable override timeHorizon;

    constructor() {
        (initialMarginRatio, maintainanceMarginRatio, timeHorizon) = (0, 0, 0);
    }

    function setValuesInside(
        int24 tickLower,
        int24 tickUpper,
        int256 sumA,
        int256 sumBInside,
        int256 sumFpInside,
        uint256 longsFeeGrowthInside,
        uint256 shortsFeeGrowthInside
    ) external {
        getValuesInside[tickLower][tickUpper].sumA = sumA;
        getValuesInside[tickLower][tickUpper].sumBInside = sumBInside;
        getValuesInside[tickLower][tickUpper].sumFpInside = sumFpInside;
        getValuesInside[tickLower][tickUpper].longsFeeGrowthInside = longsFeeGrowthInside;
        getValuesInside[tickLower][tickUpper].shortsFeeGrowthInside = shortsFeeGrowthInside;
    }

    int256 _liquidity;

    function setLiquidityRates(
        int24 tickLower,
        int24 tickUpper,
        uint256 vBasePerLiquidity,
        uint256 vTokenPerLiquidity
    ) external {
        LiquidityRate storage liquidityRate = _liquidityRates[tickLower][tickUpper];
        liquidityRate.vBasePerLiquidity = vBasePerLiquidity;
        liquidityRate.vTokenPerLiquidity = vTokenPerLiquidity;
    }

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external returns (int256 vBaseAmount, int256 vTokenAmount) {
        if (liquidity > 0) {
            _liquidity += liquidity;
        } else {
            _liquidity -= liquidity;
        }

        vBaseAmount = int256(_liquidityRates[tickLower][tickUpper].vBasePerLiquidity) * liquidity * -1;
        vTokenAmount = int256(_liquidityRates[tickLower][tickUpper].vTokenPerLiquidity) * liquidity * -1;
    }

    function getSumAX128() external pure returns (int256) {
        return 20;
    }

    function swapTokenAmount(int256 vTokenAmount) external pure returns (int256) {
        return vTokenAmount * (-4000);
    }

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external pure returns (int256 vTokenAmount, int256 vBaseAmount) {
        if (isNotional) {
            vTokenAmount = amount / 4000;
            vBaseAmount = -amount;
        } else {
            vTokenAmount = amount;
            vBaseAmount = -amount * 4000;
        }
    }

    function swapTokenNotional(int256 vTokenNotional) external pure returns (int256) {
        return vTokenNotional / (4000);
    }

    function collectAccruedProtocolFee() external pure returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = 0;
    }
}
