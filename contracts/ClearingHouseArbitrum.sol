//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { ClearingHouse } from './ClearingHouse.sol';
import { Arbitrum } from './libraries/Arbitrum.sol';
import { PriceMath } from './libraries/PriceMath.sol';

import { IOracle } from './interfaces/IOracle.sol';

contract ClearingHouseArbitrum is ClearingHouse {
    using FullMath for uint256;
    using PriceMath for uint160;

    // immutable variables do not effect storage layouts
    IOracle public immutable ethUsdcOracle;

    constructor(
        address _vPoolFactory,
        address _realBase,
        address _insuranceFundAddress,
        address _ethUsdcOracle
    ) ClearingHouse(_vPoolFactory, _realBase, _insuranceFundAddress) {
        ethUsdcOracle = IOracle(_ethUsdcOracle);
    }

    function _getFixFee() internal view override returns (uint256 fixFee) {
        uint256 gasCostWei = Arbitrum.getGasCostWei();
        uint256 ethPriceInUsdc = ethUsdcOracle.getTwapSqrtPriceX96(5 minutes).toPriceX128();
        return gasCostWei.mulDiv(ethPriceInUsdc, FixedPoint128.Q128);
    }
}
