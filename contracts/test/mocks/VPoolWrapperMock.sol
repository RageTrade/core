//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapperMock is IVPoolWrapper {
    mapping(int24 => mapping(int24 => IVPoolWrapper.WrapperValuesInside)) _getValuesInside;

    struct LiquidityRate {
        uint256 vBasePerLiquidity;
        uint256 vTokenPerLiquidity;
    }
    mapping(int24 => mapping(int24 => LiquidityRate)) internal _liquidityRates;

    // uint16 public immutable initialMarginRatio;
    // uint16 public immutable maintainanceMarginRatio;
    // uint32 public immutable twapDuration;
    // bool public whitelisted;
    IUniswapV3Pool public vPool;

    // constructor() {
    //     (initialMarginRatio, maintainanceMarginRatio, twapDuration) = (0, 0, 0);
    // }

    function VPoolWrapper__init(InitializeVPoolWrapperParams calldata params) external {}

    function updateGlobalFundingState() public {}

    function getValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        return _getValuesInside[tickLower][tickUpper];
    }

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        public
        view
        returns (WrapperValuesInside memory wrapperValuesInside)
    {
        return _getValuesInside[tickLower][tickUpper];
    }

    function setValuesInside(
        int24 tickLower,
        int24 tickUpper,
        int256 sumAX128,
        int256 sumBInsideX128,
        int256 sumFpInsideX128,
        uint256 sumFeeInsideX128
    ) external {
        _getValuesInside[tickLower][tickUpper] = IVPoolWrapper.WrapperValuesInside(
            sumAX128,
            sumBInsideX128,
            sumFpInsideX128,
            sumFeeInsideX128
        );
    }

    function setVPool(address vPoolAddress) external {
        vPool = IUniswapV3Pool(vPoolAddress);
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
    )
        external
        returns (
            int256 vBaseAmount,
            int256 vTokenAmount,
            WrapperValuesInside memory wrapperValuesInside
        )
    {
        if (liquidity > 0) {
            _liquidity += liquidity;
        } else {
            _liquidity -= liquidity;
        }

        vBaseAmount = int256(_liquidityRates[tickLower][tickUpper].vBasePerLiquidity) * liquidity;
        vTokenAmount = int256(_liquidityRates[tickLower][tickUpper].vTokenPerLiquidity) * liquidity;
        wrapperValuesInside = getValuesInside(tickLower, tickUpper);
    }

    function getSumAX128() external pure returns (int256) {
        return 20 * (1 << 128);
    }

    function getExtrapolatedSumAX128() external pure returns (int256) {
        return 20 * (1 << 128);
    }

    function swapTokenAmount(int256 vTokenAmount) external pure returns (int256) {
        return vTokenAmount * (-4000);
    }

    function swapToken(
        int256 amount,
        uint160, // sqrtPriceLimit,
        bool isNotional
    ) external pure returns (int256 vTokenAmount, int256 vBaseAmount) {
        if (isNotional) {
            vTokenAmount = -amount / 4000;
            vBaseAmount = amount;
        } else {
            vTokenAmount = -amount;
            vBaseAmount = amount * 4000;
        }
    }

    function swapTokenNotional(int256 vTokenNotional) external pure returns (int256) {
        return vTokenNotional / (4000);
    }

    function collectAccruedProtocolFee() external pure returns (uint256 accruedProtocolFeeLast) {
        accruedProtocolFeeLast = 0;
    }

    function setOracle(address _oracle) external pure {
        //Do nothing
    }
}
