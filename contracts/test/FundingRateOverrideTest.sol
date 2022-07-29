// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';

import { FundingRateOverride } from '../libraries/FundingRateOverride.sol';
import { SignedFullMath } from '../libraries/SignedFullMath.sol';

contract FundingRateOverrideTest {
    using FundingRateOverride for FundingRateOverride.Info;

    FundingRateOverride.Info public fundingRateOverride;

    function PREFIX() external pure returns (bytes32) {
        return FundingRateOverride.PREFIX;
    }

    function NULL_VALUE() external pure returns (bytes32) {
        return FundingRateOverride.NULL_VALUE;
    }

    function setNull() external {
        fundingRateOverride.setNull();
    }

    function setOracle(AggregatorV3Interface oracle) external {
        fundingRateOverride.setOracle(oracle);
    }

    function setValueX128(int256 fundingRateOverrideX128) external {
        fundingRateOverride.setValueX128(fundingRateOverrideX128);
    }

    function set(bytes32 data) external {
        fundingRateOverride.set(data);
    }

    function getValueX128() external view returns (bool success, int256 fundingRateOverrideX128) {
        return fundingRateOverride.getValueX128();
    }

    function packOracleAddress(address oracleAddress) external pure returns (bytes32 data) {
        return FundingRateOverride.packOracleAddress(oracleAddress);
    }

    function packInt256(int256 fundingRateOverrideX128) external pure returns (bytes32 data) {
        return FundingRateOverride.packInt256(fundingRateOverrideX128);
    }

    function unpackOracleAddress(bytes32 data) external pure returns (address oracleAddress) {
        return FundingRateOverride.unpackOracleAddress(data);
    }

    function unpackInt256(bytes32 data) external pure returns (int256 fundingRateOverrideX128) {
        return FundingRateOverride.unpackInt256(data);
    }
}
