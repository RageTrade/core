//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@134dd3v/uniswap-v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { VTokenAddress, VTokenLib } from './VTokenLib.sol';
import { VTokenPosition } from './VTokenPosition.sol';

import { Constants } from '../utils/Constants.sol';

import { console } from 'hardhat/console.sol';

library DepositTokenSet {
    using VTokenLib for VTokenAddress;
    using Uint32L8ArrayLib for uint32[8];
    using SignedFullMath for int256;
    int256 internal constant Q96 = 0x1000000000000000000000000;

    struct Info {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => uint256) deposits;
        uint256[100] emptySlots; // reserved for adding variables when upgrading logic
    }

    // add overrides that accept vToken or truncated
    function increaseBalance(
        Info storage info,
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) internal {
        // consider vbase as always active because it is base (actives are needed for margin check)
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            info.active.include(vTokenAddress.truncate());
        }
        info.deposits[vTokenAddress.truncate()] += amount;
    }

    function decreaseBalance(
        Info storage info,
        VTokenAddress vTokenAddress,
        uint256 amount,
        Constants memory constants
    ) internal {
        uint32 truncated = vTokenAddress.truncate();

        // consider vbase as always active because it is base (actives are needed for margin check)
        if (!vTokenAddress.eq(constants.VBASE_ADDRESS)) {
            info.active.include(truncated);
        }

        require(info.deposits[truncated] >= amount);
        info.deposits[truncated] -= amount;
    }

    function getAllDepositAccountMarketValue(
        Info storage set,
        mapping(uint32 => VTokenAddress) storage vTokenAddresses,
        Constants memory constants
    ) internal view returns (int256) {
        int256 accountMarketValue;
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];

            if (truncated == 0) break;
            VTokenAddress vTokenAddress = vTokenAddresses[truncated];

            accountMarketValue += int256(set.deposits[truncated]).mulDiv(
                vTokenAddress.getRealTwapPriceX128(constants),
                FixedPoint128.Q128
            );
        }

        accountMarketValue += int256(set.deposits[VTokenAddress.wrap(constants.VBASE_ADDRESS).truncate()]);

        return accountMarketValue;
    }
}
