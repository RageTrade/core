// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IVQuote } from './IVQuote.sol';
import { IVToken } from './IVToken.sol';
import { IClearingHouse } from './IClearingHouse.sol';

interface IVPoolWrapper {
    struct InitializeVPoolWrapperParams {
        IClearingHouse clearingHouse; // address of clearing house contract (proxy)
        IVToken vToken; // address of vToken contract
        IVQuote vQuote; // address of vQuote contract
        IUniswapV3Pool vPool; // address of Uniswap V3 Pool contract, created using vToken and vQuote
        uint24 liquidityFeePips; // liquidity fee fraction (in 1e6)
        uint24 protocolFeePips; // protocol fee fraction (in 1e6)
    }

    struct SwapResult {
        int256 amountSpecified; // amount of tokens/vQuote which were specified in the swap request
        int256 vTokenIn; // actual amount of vTokens paid by account to the Pool
        int256 vQuoteIn; // actual amount of vQuotes paid by account to the Pool
        uint256 liquidityFees; // actual amount of fees paid by account to the Pool
        uint256 protocolFees; // actual amount of fees paid by account to the Protocol
        uint160 sqrtPriceX96Start; // sqrt price at the beginning of the swap
        uint160 sqrtPriceX96End; // sqrt price at the end of the swap
    }

    struct WrapperValuesInside {
        int256 sumAX128; // sum of all the A terms in the pool
        int256 sumBInsideX128; // sum of all the B terms in side the tick range in the pool
        int256 sumFpInsideX128; // sum of all the Fp terms in side the tick range in the pool
        uint256 sumFeeInsideX128; // sum of all the fee terms in side the tick range in the pool
    }

    event Swap(SwapResult swapResult);

    event Mint(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 vTokenPrincipal, uint256 vQuotePrincipal);

    event Burn(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 vTokenPrincipal, uint256 vQuotePrincipal);

    event AccruedProtocolFeeCollected(uint256 amount);

    event LiquidityFeeUpdated(uint24 liquidityFeePips);

    event ProtocolFeeUpdated(uint24 protocolFeePips);

    event FundingRateOverrideUpdated(int256 fundingRateOverrideX128);

    function __initialize_VPoolWrapper(InitializeVPoolWrapperParams memory params) external;

    function vPool() external view returns (IUniswapV3Pool);

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
    ) external returns (SwapResult memory swapResult);

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

    function liquidityFeePips() external view returns (uint24);

    function protocolFeePips() external view returns (uint24);

    function updateGlobalFundingState(uint256 realPriceX128, uint256 virtualPriceX128) external;

    function collectAccruedProtocolFee() external returns (uint256 accruedProtocolFeeLast);
}
