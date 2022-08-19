// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

/// @title Protocol storage functions
/// @dev This is used as main storage interface containing protocol info
library AtomicVTokenSwap {
    struct Info {
        uint256 senderAccountId;
        uint256 receiverAccountId;
        int256 vTokenAmount;
        int256 vQuoteAmount;
        uint32 poolId;
        uint64 timelock;
        bool complete;
    }
}
