// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ArbSys {
    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);
}

/// @title Library for getting block number for the current chain
library Block {
    /// @notice Get block number
    /// @return block number as uint32
    function number() internal view returns (uint32) {
        uint256 chainId = block.chainid;
        if (chainId == 42161 || chainId == 421611 || chainId == 421612) {
            return uint32(ArbSys(address(100)).arbBlockNumber());
        } else {
            return uint32(block.number);
        }
    }
}
