//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { VTokenAddress } from '../libraries/VTokenLib.sol';

import { IVBase } from './IVBase.sol';
import { IVToken } from './IVToken.sol';
import { IClearingHouse } from './IClearingHouse.sol';

interface IVPoolWrapper {
    struct WrapperValuesInside {
        int256 sumAX128;
        int256 sumBInsideX128;
        int256 sumFpInsideX128;
        uint256 sumFeeInsideX128;
    }

    event Swap(int256 vTokenIn, int256 vBaseIn, uint256 liquidityFees, uint256 protocolFees);

    struct InitializeVPoolWrapperParams {
        IClearingHouse clearingHouse;
        IVToken vTokenAddress;
        IVBase vBase;
        IUniswapV3Pool vPool;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
        uint24 UNISWAP_V3_DEFAULT_FEE_TIER;
    }

    // address _vTokenAddress,
    // address _vPoolAddress,
    // address _oracleAddress,
    // uint24 _liquidityFeePips,
    // uint24 _protocolFeePips,
    // uint16 _initialMarginRatio,
    // uint16 _maintainanceMarginRatio,
    // uint32 _twapDuration,
    // bool _whitelisted,
    // address _vBaseAddress
    function __VPoolWrapper_init(InitializeVPoolWrapperParams calldata params) external;

    // function twapDuration() external view returns (uint32);

    function vPool() external view returns (IUniswapV3Pool);

    function updateGlobalFundingState() external;

    // function initialMarginRatio() external view returns (uint16);

    // function maintainanceMarginRatio() external view returns (uint16);

    // function whitelisted() external view returns (bool);

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside);

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside);

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
        );

    function getSumAX128() external view returns (int256);

    function getExtrapolatedSumAX128() external view returns (int256);

    function swapToken(
        int256 amount,
        uint160 sqrtPriceLimit,
        bool isNotional
    ) external returns (int256 vTokenAmount, int256 vBaseAmount);

    function collectAccruedProtocolFee() external returns (uint256 accruedProtocolFeeLast);

    // function setOracle(address oracle_) external;
}
