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
import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { Account } from './Account.sol';

// TODO this lib seems point less. Is it needed?
library CTokenLib {
    using CTokenLib for IClearingHouse.CollateralSettings;
    using FullMath for uint256;
    using PriceMath for uint160;
    using UniswapV3PoolHelper for IUniswapV3Pool;

    function eq(IClearingHouse.Collateral storage a, IClearingHouse.Collateral storage b) internal view returns (bool) {
        return address(a.token) == address(b.token);
    }

    function eq(IClearingHouse.Collateral storage a, address b) internal view returns (bool) {
        return address(a.token) == b;
    }

    // TODO is this used anywhere?
    function decimals(IClearingHouse.Collateral storage collateral) internal view returns (uint8) {
        return IERC20Metadata(address(collateral.token)).decimals();
    }

    function truncate(address realTokenAddress) internal pure returns (uint32) {
        return uint32(uint160(realTokenAddress));
    }

    function truncate(IClearingHouse.Collateral storage collateral) internal view returns (uint32) {
        // TODO truncate method is common in both CTokenLib and VTokenLib
        return uint32(uint160(address(collateral.token)));
    }

    function getRealTwapPriceX128(IClearingHouse.Collateral storage collateral)
        internal
        view
        returns (uint256 priceX128)
    {
        return collateral.settings.oracle.getTwapPriceX128(collateral.settings.twapDuration);
    }
}
