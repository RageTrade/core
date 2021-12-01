//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Oracle } from '../libraries/Oracle.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract OracleTest {
    using Oracle for address;

    function checkPrice() external pure {
        // TODO add tests
        // assert(address(1).getPrice() == 0);
    }

    function getTwapTick(IUniswapV3Pool pool, uint32 twapDuration) external view returns (int24) {
        return Oracle.getTwapTick(pool, twapDuration);
    }
}
