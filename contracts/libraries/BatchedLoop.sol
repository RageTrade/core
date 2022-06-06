// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Math } from '@openzeppelin/contracts/utils/math/Math.sol';

/// @title Batched Loop Library
/// @notice Aids to perform a lengthy loop in seperate txs
library BatchedLoop {
    uint256 constant NULL = 0;

    struct Info {
        uint256 progress; // of array element to resume the progress from
    }

    /// @notice Resumes the loop from where it left of previously
    /// @param loop: the loop object to resume (this is storage ref and val is mutated)
    /// @param startAt: the index to start from
    /// @param endBefore: the index to end at
    /// @param batchSize: number of iterations to perform in this batch
    /// @param execute: the function to execute for each iteration
    /// @dev translates to: for(uint i = startAt; i < endBefore; i++) { execute(i); }
    function iterate(
        BatchedLoop.Info storage loop,
        uint256 startAt,
        uint256 endBefore,
        uint256 batchSize,
        function(uint256) execute
    ) internal returns (bool completed) {
        // resume the loop from the stored progress else use startAt
        uint256 from = loop.progress;
        if (from == NULL) from = startAt;

        // use endBefore if batchSize is zero, else calculate end index
        uint256 to = batchSize == NULL ? endBefore : Math.min(from + batchSize, endBefore);

        // executes upto (to - 1)
        while (from < to) {
            execute(from);
            from++;
        }

        if (completed = (to == endBefore)) {
            // if loop was completed then reset the progress
            loop.progress = NULL;
        } else {
            // store the progress if partial execution of the loop
            loop.progress = to;
        }
    }

    /// @notice Checks if the loop is in progress
    /// @param loop: the loop object
    /// @return true if the loop is in progress else false
    function isInProgress(BatchedLoop.Info storage loop) internal view returns (bool) {
        return loop.progress != NULL;
    }
}
