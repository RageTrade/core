// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { AddressHelper } from '../libraries/AddressHelper.sol';
import { PriceMath } from '../libraries/PriceMath.sol';

import { IOracle } from '../interfaces/IOracle.sol';

contract ChainlinkOracle is IOracle {
    using AddressHelper for address;
    using FullMath for uint256;
    using SafeCast for uint256;
    using PriceMath for uint256;

    AggregatorV3Interface public aggregator;
    uint8 immutable vTokenDecimals;
    uint8 immutable vQuoteDecimals;

    error NotEnoughHistory();
    error IllegalAggregatorAddress(address aggregator);

    constructor(
        address _aggregator,
        uint8 _vTokenDecimals,
        uint8 _vQuoteDecimals
    ) {
        if (_aggregator.isZero()) revert IllegalAggregatorAddress(address(0));
        aggregator = AggregatorV3Interface(_aggregator);
        vTokenDecimals = _vTokenDecimals;
        vQuoteDecimals = _vQuoteDecimals;
    }

    function getTwapPriceX128(uint32 twapDuration) public view returns (uint256 priceX128) {
        priceX128 = getPrice(twapDuration);
        priceX128 = priceX128.mulDiv(
            FixedPoint128.Q128 * 10**(vQuoteDecimals),
            10**(vTokenDecimals + aggregator.decimals())
        );
    }

    function getPrice(uint256 twapDuration) internal view returns (uint256) {
        (uint80 round, uint256 latestPrice, uint256 latestTS) = _getLatestRoundData();
        uint256 endTS = block.timestamp;
        uint256 thresholdTS = endTS - twapDuration;

        //If twap duration = 0 or less data available just return latestPrice
        if (twapDuration == 0 || round == 0 || latestTS <= thresholdTS) {
            return latestPrice;
        }

        uint256 totalTime = endTS - latestTS;
        uint256 twap = latestPrice * totalTime;
        uint256 periodLength;
        uint256 startTS;
        uint256 periodPrice;

        endTS = latestTS;

        //Aggregate prices for all the eligible rounds before thresholdTS i.e. adds price*periodLength to twap
        //For the last eligible round goes till thresholdTS only
        while (true) {
            //If 0 round is reached before reaching thresholdTS then just consider the available data
            if (round == 0) {
                return totalTime == 0 ? latestPrice : twap / totalTime;
            }

            round = round - 1;
            (, periodPrice, startTS) = _getRoundData(round);

            //If the starting time of a period is lesser than threshold timestamp (now-twapDuration) then period is thresholdTS -> endTS
            if (startTS <= thresholdTS) {
                twap += periodPrice * (endTS - thresholdTS);
                break;
            }

            // In normal case where thresholdTS < startTS. The whole period is considered i.e. startTS -> endTS
            periodLength = (endTS - startTS);
            twap += (periodPrice * periodLength);
            totalTime += periodLength;

            //endTS of previous period = startTS of current period
            endTS = startTS;
        }

        //Divide the accumulated value by the whole duration
        return twap == 0 ? latestPrice : twap / twapDuration;
    }

    function _getLatestRoundData()
        private
        view
        returns (
            uint80,
            uint256 finalPrice,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTS, ) = aggregator.latestRoundData();
        finalPrice = uint256(latestPrice);

        if (latestPrice < 0 && round <= 0) revert NotEnoughHistory();

        if (latestPrice < 0) {
            (round, finalPrice, latestTS) = _getRoundData(round - 1);
        }
        return (round, finalPrice, latestTS);
    }

    function _getRoundData(uint80 _round)
        private
        view
        returns (
            uint80,
            uint256,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTS, ) = aggregator.getRoundData(_round);
        while (latestPrice < 0 && round > 0) {
            round = round - 1;
            (, latestPrice, , latestTS, ) = aggregator.getRoundData(round);
        }
        if (latestPrice < 0 && round <= 0) revert NotEnoughHistory();
        return (round, uint256(latestPrice), latestTS);
    }
}
