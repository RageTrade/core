//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { Address } from '@openzeppelin/contracts/utils/Address.sol';
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

contract ChainlinkOracle {
    using SafeMath for uint256;
    using FullMath for uint256;
    using SafeCast for uint256;
    using Address for address;

    AggregatorV3Interface public aggregator;

    constructor(address _aggregator) {
        require(_aggregator != address(0), 'invalid aggregator address');
        aggregator = AggregatorV3Interface(_aggregator);
    }

    function decimals() internal view returns (uint8) {
        return aggregator.decimals();
    }

    function getTwapPriceX128(uint32 interval) external view returns (uint256 priceX128) {
        priceX128 = getPrice(interval);
        priceX128 = priceX128.mulDiv(FixedPoint128.Q128, 10**decimals()); // TODO more decimals?
    }

    function getPrice(uint256 interval) internal view returns (uint256) {
        // there are 3 timestamps: base(our target), previous & current
        // base: now - _interval
        // current: the current round timestamp from aggregator
        // previous: the previous round timestamp from aggregator
        // now >= previous > current > = < base
        //
        //  while loop i = 0
        //  --+------+-----+-----+-----+-----+-----+
        //         base                 current  now(previous)
        //
        //  while loop i = 1
        //  --+------+-----+-----+-----+-----+-----+
        //         base           current previous now

        (uint80 round, uint256 latestPrice, uint256 latestTimestamp) = _getLatestRoundData();
        uint256 timestamp = block.timestamp;
        uint256 baseTimestamp = timestamp.sub(interval);

        // if the latest timestamp <= base timestamp, which means there's no new price, return the latest price
        if (interval == 0 || round == 0 || latestTimestamp <= baseTimestamp) {
            return latestPrice;
        }

        // rounds are like snapshots, latestRound means the latest price snapshot; follow Chainlink's namings here
        uint256 previousTimestamp = latestTimestamp;
        uint256 cumulativeTime = timestamp.sub(previousTimestamp);
        uint256 weightedPrice = latestPrice.mul(cumulativeTime);
        uint256 timeFraction;
        while (true) {
            if (round == 0) {
                // to prevent from div 0 error, return the latest price if `cumulativeTime == 0`
                return cumulativeTime == 0 ? latestPrice : weightedPrice.div(cumulativeTime);
            }

            round = round - 1;
            (, uint256 currentPrice, uint256 currentTimestamp) = _getRoundData(round);

            // check if the current round timestamp is earlier than the base timestamp
            if (currentTimestamp <= baseTimestamp) {
                // the weighted time period is (base timestamp - previous timestamp)
                // ex: now is 1000, interval is 100, then base timestamp is 900
                // if timestamp of the current round is 970, and timestamp of NEXT round is 880,
                // then the weighted time period will be (970 - 900) = 70 instead of (970 - 880)
                weightedPrice = weightedPrice.add(currentPrice.mul(previousTimestamp.sub(baseTimestamp)));
                break;
            }

            timeFraction = previousTimestamp.sub(currentTimestamp);
            weightedPrice = weightedPrice.add(currentPrice.mul(timeFraction));
            cumulativeTime = cumulativeTime.add(timeFraction);
            previousTimestamp = currentTimestamp;
        }

        return weightedPrice == 0 ? latestPrice : weightedPrice.div(interval);
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
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = aggregator.latestRoundData();
        finalPrice = uint256(latestPrice);
        if (latestPrice < 0) {
            _requireEnoughHistory(round);
            (round, finalPrice, latestTimestamp) = _getRoundData(round - 1);
        }
        return (round, finalPrice, latestTimestamp);
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
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = aggregator.getRoundData(_round);
        while (latestPrice < 0) {
            _requireEnoughHistory(round);
            round = round - 1;
            (, latestPrice, , latestTimestamp, ) = aggregator.getRoundData(round);
        }
        return (round, uint256(latestPrice), latestTimestamp);
    }

    function _requireEnoughHistory(uint80 _round) private pure {
        require(_round > 0, 'not enough history');
    }
}
