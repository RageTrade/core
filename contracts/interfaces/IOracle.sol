//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IOracle {
    error NotEnoughHistory();
    error ZeroAddress();

    function getTwapPriceX128(uint32 twapDuration) external view returns (uint256 priceX128);
}
