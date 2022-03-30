// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IExtsload } from '../interfaces/IExtsload.sol';
import { IClearingHouse } from '../interfaces/IClearingHouse.sol';

import { ClearingHouseExtsload } from '../extsloads/ClearingHouseExtsload.sol';

import 'hardhat/console.sol';

contract ClearingHouseExtsloadTest {
    modifier notView() {
        assembly {
            if iszero(1) {
                sstore(0, 0)
            }
        }
        _;
    }

    function pools_vPool_and_settings_twapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (address vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.pools_vPool_and_settings_twapDuration(clearingHouse, poolId);
    }

    function check_pools_vPool_and_settings_twapDuration(IClearingHouse clearingHouse, uint32 poolId)
        public
        notView
        returns (address vPool, uint32 twapDuration)
    {
        (vPool, twapDuration) = ClearingHouseExtsload.pools_vPool_and_settings_twapDuration(clearingHouse, poolId);
        clearingHouse.getPoolInfo(poolId);
    }

    function pools_vPool(IClearingHouse clearingHouse, uint32 poolId) public view returns (address vPool) {
        vPool = ClearingHouseExtsload.pools_vPool(clearingHouse, poolId);
    }

    function pools_settings(IClearingHouse clearingHouse, uint32 poolId)
        public
        view
        returns (
            uint16 initialMarginRatioBps,
            uint16 maintainanceMarginRatioBps,
            uint16 maxVirtualPriceDeviationRatioBps,
            uint32 twapDuration,
            bool isAllowedForTrade,
            bool isCrossMargined,
            address oracle
        )
    {
        return ClearingHouseExtsload.pools_settings(clearingHouse, poolId);
    }
}
