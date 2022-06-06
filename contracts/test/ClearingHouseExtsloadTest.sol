// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IExtsload } from '../interfaces/IExtsload.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVQuote } from '../interfaces/IVQuote.sol';

import { ClearingHouseExtsload } from '../extsloads/ClearingHouseExtsload.sol';

contract ClearingHouseExtsloadTest {
    modifier notView() {
        assembly {
            if iszero(1) {
                sstore(0, 0)
            }
        }
        _;
    }

    function getVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.getVPoolAndTwapDuration(clearingHouse, poolId);
    }

    function checkVPoolAndTwapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        notView
        returns (IUniswapV3Pool vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.getVPoolAndTwapDuration(clearingHouse, poolId);
    }

    function getVPool(IClearingHouse clearingHouse, uint32 poolId) public view returns (IUniswapV3Pool vPool) {
        vPool = ClearingHouseExtsload.getVPool(clearingHouse, poolId);
    }

    function getPoolSettings(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (IClearingHouse.PoolSettings memory settings)
    {
        return ClearingHouseExtsload.getPoolSettings(clearingHouse, poolId);
    }

    function isPoolIdAvailable(IClearingHouse clearingHouse, uint32 poolId) public view returns (bool) {
        return ClearingHouseExtsload.isPoolIdAvailable(clearingHouse, poolId);
    }

    function getPoolInfo(IClearingHouse clearingHouse, uint32 poolId) public view returns (IClearingHouse.Pool memory) {
        return ClearingHouseExtsload.getPoolInfo(clearingHouse, poolId);
    }

    function getProtocolInfo(IClearingHouse clearingHouse)
        external
        view
        returns (
            IERC20 settlementToken,
            IVQuote vQuote,
            IClearingHouse.LiquidationParams memory liquidationParams,
            uint256 minRequiredMargin,
            uint256 removeLimitOrderFee,
            uint256 minimumOrderNotional
        )
    {
        return ClearingHouseExtsload.getProtocolInfo(clearingHouse);
    }

    function getCollateralInfo(IClearingHouse clearingHouse, uint32 collateralId)
        external
        view
        returns (IClearingHouse.Collateral memory)
    {
        return ClearingHouseExtsload.getCollateralInfo(clearingHouse, collateralId);
    }
}
