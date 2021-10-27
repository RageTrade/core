//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IOracleContract.sol';

contract OracleContract is IOracleContract {
    function getSqrtPrice(uint32 twapDuration) external pure returns (uint160) {
        return 4000000000000000000000000;
    }
}
