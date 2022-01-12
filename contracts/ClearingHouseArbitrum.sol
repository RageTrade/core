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

    IOracle public ethUsdcOracle;

    function ClearingHouseArbitrum__init(
        address _vPoolFactory,
        address _realBase,
        address _insuranceFundAddress,
        address _VBASE_ADDRESS,
        address _UNISWAP_V3_FACTORY_ADDRESS,
        uint24 _UNISWAP_V3_DEFAULT_FEE_TIER,
        bytes32 _UNISWAP_V3_POOL_BYTE_CODE_HASH,
        address _ethUsdcOracle
    ) public {
        ClearingHouse__init(
            _vPoolFactory,
            _realBase,
            _insuranceFundAddress,
            _VBASE_ADDRESS,
            _UNISWAP_V3_FACTORY_ADDRESS,
            _UNISWAP_V3_DEFAULT_FEE_TIER,
            _UNISWAP_V3_POOL_BYTE_CODE_HASH
        );
        ethUsdcOracle = IOracle(_ethUsdcOracle);
    }

    function _getFixFee() internal view override returns (uint256 fixFee) {
        uint256 gasCostWei = Arbitrum.getGasCostWei();
        uint256 ethPriceInUsdc = ethUsdcOracle.getTwapSqrtPriceX96(5 minutes).toPriceX128();
        return gasCostWei.mulDiv(ethPriceInUsdc, FixedPoint128.Q128);
    }
}
