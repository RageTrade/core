//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IChainlinkOracle {
    function getTwapPriceX128(
        uint32 twapDuration,
        uint8 tokenDecimals,
        uint8 baseDecimals
    ) external view returns (uint256 priceX128);
}
