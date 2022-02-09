// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IRealOracle } from '../../interfaces/IRealOracle.sol';
import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';


contract AggregatorMock is AggregatorV3Interface {

    struct Round {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    string constant _desc = "Mock Aggregator";
    uint256 constant _cVersion = 1;
    uint8 constant _numDecimals = 8;
    Round[6] history;

    function setHistory(Round[6] memory _history) external {
        history = _history;
    }

    function decimals() external pure returns (uint8 numDecimals) {
        numDecimals = _numDecimals;
    }

    function description() external pure returns (string memory desc) {
        desc = _desc;
    }

    function version() external pure returns (uint256 cVersion) {
        cVersion = _cVersion;
    }
    
    function getRoundData(uint80 _roundId) external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        for (uint i=0; i<history.length; i++) {
            if (history[i].roundId == _roundId) {
                Round memory round = history[i];
                return (
                    round.roundId,
                    round.answer,
                    round.startedAt,
                    round.updatedAt,
                    round.answeredInRound
                );
            }
        }
        return (
            0, 0, 0, 0, 0
        );
    }

    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
        for (uint i = history.length; i >= 0; --i) {
            if (history[i].roundId != 0) {
                Round memory round = history[i];
                return (
                    round.roundId,
                    round.answer,
                    round.startedAt,
                    round.updatedAt,
                    round.answeredInRound
                );
            }
        }
        return (
            0, 0, 0, 0, 0
        );
    }
    
}