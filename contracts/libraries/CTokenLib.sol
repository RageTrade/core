//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { PriceMath } from './PriceMath.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { Account } from './Account.sol';

library CTokenLib {
    using CTokenLib for CToken;
    using FullMath for uint256;
    using PriceMath for uint160;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    struct CToken {
        address tokenAddress;
        address oracleAddress;
        uint32 oracleTimeHorizon;
        bool supported;
    }

    function eq(CToken storage a, CToken storage b) internal view returns (bool) {
        return a.tokenAddress == b.tokenAddress;
    }

    function eq(CToken storage a, address b) internal view returns (bool) {
        return a.tokenAddress == b;
    }

    function decimals(CToken storage token) internal view returns (uint8) {
        return IERC20Metadata(token.tokenAddress).decimals();
    }

    function truncate(address realTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(realTokenAddress));
    }

    function truncate(CToken storage token) internal view returns (uint32) {
        return uint32(uint160(token.tokenAddress));
    }

    function realToken(CToken storage token) internal view returns (IERC20) {
        return IERC20(token.tokenAddress);
    }

    function oracle(CToken storage token) internal view returns (IOracle) {
        return IOracle(token.oracleAddress);
    }

    function getRealTwapPriceX128(RToken storage token) internal view returns (uint256 priceX128) {
        return token.oracle().getTwapPriceX128(token.oracleTimeHorizon);
    }
}