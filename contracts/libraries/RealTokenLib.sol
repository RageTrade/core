//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint96 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint96.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { UniswapV3PoolHelper } from './UniswapV3PoolHelper.sol';
import { PriceMath } from './PriceMath.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { Constants } from '../utils/Constants.sol';

library RealTokenLib {
    struct RealToken {
        address tokenAddress;
        address oracleAddress;
        uint32 oracleTimeHorizon;
    }

    using RealTokenLib for RealToken;
    using FullMath for uint256;
    using PriceMath for uint160;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    function eq(RealToken storage a, RealToken storage b) internal view returns (bool) {
        return a.tokenAddress == b.tokenAddress;
    }

    function eq(RealToken storage a, address b) internal view returns (bool) {
        return a.tokenAddress == b;
    }

    function truncate(RealToken storage token) internal view returns (uint32) {
        return uint32(uint160(token.tokenAddress));
    }

    function realToken(RealToken storage token) internal view returns (IERC20) {
        return IERC20(token.tokenAddress);
    }

    function oracle(RealToken storage token) internal view returns (IOracle) {
        return IOracle(token.oracleAddress);
    }

    function getRealTwapSqrtPriceX96(RealToken storage token) internal view returns (uint160 sqrtPriceX96) {
        return token.oracle().getTwapSqrtPriceX96(token.oracleTimeHorizon);
    }

    function getRealTwapPriceX128(RealToken storage token) internal view returns (uint256 priceX128) {
        return token.getRealTwapSqrtPriceX96().toPriceX128();
    }
}
