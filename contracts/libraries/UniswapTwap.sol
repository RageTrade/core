//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './UniswapTickMath.sol';

library UniswapTwap {
    function getSqrtPrice(address pool, uint32 twapDuration) internal view returns (uint160 sqrtPriceX96) {
        int24 twapTick = getTick(pool, twapDuration);
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(twapTick);
    }

    function getTick(address pool, uint32 twapDuration) internal view returns (int24 twapTick) {
        uint32 _twapDuration = twapDuration;
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgo);
        twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_twapDuration))); // TODO : Twap duration has to be under 2 ^ 16 because of this
    }
}
