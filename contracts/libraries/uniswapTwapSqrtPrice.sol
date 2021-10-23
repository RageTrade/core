//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './UniswapTickMath.sol';

library UniswapTwapSqrtPrice {
    function get(address pool, uint32 twapDuration) internal view returns (uint160 sqrtPriceX96) {
        uint32 _twapDuration = twapDuration;
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgo);
        int24 twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_twapDuration))); // TODO : Twap duration has to be under 2 ^ 16 because of this
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);
    }
}
