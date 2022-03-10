//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IVQuote } from './IVQuote.sol';
import { IVToken } from './IVToken.sol';
import { IClearingHouse } from './IClearingHouse.sol';

interface IVPoolWrapper {
    struct WrapperValuesInside {
        int256 sumAX128;
        int256 sumBInsideX128;
        int256 sumFpInsideX128;
        uint256 sumFeeInsideX128;
    }

    event Swap(int256 vTokenIn, int256 vQuoteIn, uint256 liquidityFees, uint256 protocolFees);

    event Mint(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 vTokenPrincipal, uint256 vQuotePrincipal);

    event Burn(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 vTokenPrincipal, uint256 vQuotePrincipal);

    event AccruedProtocolFeeCollected(uint256 amount);

    event LiquidityFeeUpdated(uint24 liquidityFeePips);

    event ProtocolFeeUpdated(uint24 protocolFeePips);

    struct InitializeVPoolWrapperParams {
        IClearingHouse clearingHouse;
        IVToken vToken;
        IVQuote vQuote;
        IUniswapV3Pool vPool;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
        uint24 UNISWAP_V3_DEFAULT_FEE_TIER;
    }

    function __initialize_VPoolWrapper(InitializeVPoolWrapperParams memory params) external;

    function vPool() external view returns (IUniswapV3Pool);

    function updateGlobalFundingState() external;

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside);

    function getExtrapolatedValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (WrapperValuesInside memory wrapperValuesInside);

    function swap(
        bool swapVTokenForVQuote, // zeroForOne
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 vTokenAmount, int256 vQuoteAmount);

    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        returns (
            uint256 vTokenPrincipal,
            uint256 vQuotePrincipal,
            WrapperValuesInside memory wrapperValuesInside
        );

    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        external
        returns (
            uint256 vTokenPrincipal,
            uint256 vQuotePrincipal,
            WrapperValuesInside memory wrapperValuesInside
        );

    function getSumAX128() external view returns (int256);

    function getExtrapolatedSumAX128() external view returns (int256);

    function collectAccruedProtocolFee() external returns (uint256 accruedProtocolFeeLast);

    function uniswapFeePips() external view returns (uint24);

    function liquidityFeePips() external view returns (uint24);

    function protocolFeePips() external view returns (uint24);
}
