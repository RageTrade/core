//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/SafeCast.sol';
import '../../interfaces/IVPoolWrapper.sol';
import '../../interfaces/IVPoolWrapperDeployer.sol';
import { VTokenAddress, VTokenLib, IUniswapV3Pool, Constants } from '../../libraries/VTokenLib.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import { IUniswapV3SwapCallback } from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '../../interfaces/IVBase.sol';
import '../../interfaces/IVToken.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVToken } from '../../interfaces/IVToken.sol';
import { IUniswapV3PoolDeployer } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3PoolDeployer.sol';

import { FixedPoint128 } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FullMath.sol';
import { FundingPayment } from '../../libraries/FundingPayment.sol';
import { SimulateSwap } from '../../libraries/SimulateSwap.sol';
import { Tick } from '../../libraries/Tick.sol';
import { TickMath } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/TickMath.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { SignedFullMath } from '../../libraries/SignedFullMath.sol';
import { UniswapV3PoolHelper } from '../../libraries/UniswapV3PoolHelper.sol';
import { VPoolWrapper } from '../../VPoolWrapper.sol';

import { Oracle } from '../../libraries/Oracle.sol';

import { console } from 'hardhat/console.sol';

contract VPoolWrapperMockRealistic is VPoolWrapper {
    uint48 public blockTimestamp;

    constructor() VPoolWrapper() {
        fpGlobal.timestampLast = 0;
    }

    function setFpGlobalLastTimestamp(uint48 timestamp) external {
        fpGlobal.timestampLast = timestamp;
    }

    function setBlockTimestamp(uint48 timestamp) external {
        blockTimestamp = timestamp;
    }

    function _blockTimestamp() internal view virtual override returns (uint48) {
        return blockTimestamp;
    }
}
