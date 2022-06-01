// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { BatchedLoop } from '../libraries/BatchedLoop.sol';

contract BatchedLoopTest {
    using BatchedLoop for BatchedLoop.Info;

    BatchedLoop.Info public loop;

    uint256[] input;
    uint256[] output;

    function setInput(uint256[] memory _input) public {
        input = _input;
    }

    function getOutput() public view returns (uint256[] memory) {
        return output;
    }

    function isInProgress() public view returns (bool) {
        return loop.isInProgress();
    }

    function iterate(uint256 iterations, bool expectTrue) public {
        require(
            loop.iterate({
                startAt: 0,
                endBefore: input.length,
                batchSize: iterations,
                execute: forEachArrayElement
            }) == expectTrue
        );
    }

    function forEachArrayElement(uint256 i) private {
        output.push(input[i]);
    }
}

contract BatchedLoopTest2 {
    using BatchedLoop for BatchedLoop.Info;

    BatchedLoop.Info public iteration;

    uint256[] output;

    function getOutput() public view returns (uint256[] memory) {
        return output;
    }

    function isInProgress() public view returns (bool) {
        return iteration.isInProgress();
    }

    function iterate(
        uint256 startAt,
        uint256 endBefore,
        uint256 batchSize,
        bool expectTrue
    ) public {
        require(iteration.iterate(startAt, endBefore, batchSize, squarePlusOne) == expectTrue);
    }

    function squarePlusOne(uint256 i) private {
        output.push(i * i + 1);
    }
}
