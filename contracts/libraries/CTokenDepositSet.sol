//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from './Account.sol';
import { AddressHelper } from './AddressHelper.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';

import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { console } from 'hardhat/console.sol';

// TODO rename to collateral deposit set
library CTokenDepositSet {
    using AddressHelper for address;
    using Uint32L8ArrayLib for uint32[8];
    using SignedFullMath for int256;
    using SafeCast for uint256;

    struct Info {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => uint256) deposits;
        uint256[100] _emptySlots; // reserved for adding variables when upgrading logic
    }

    // add overrides that accept vToken or truncated
    function increaseBalance(
        Info storage info,
        uint32 collateralId,
        uint256 amount
    ) internal {
        // consider vbase as always active because it is base (actives are needed for margin check)
        info.active.include(collateralId);

        info.deposits[collateralId] += amount;
    }

    function decreaseBalance(
        Info storage info,
        uint32 collateralId,
        uint256 amount
    ) internal {
        require(info.deposits[collateralId] >= amount);
        info.deposits[collateralId] -= amount;

        if (info.deposits[collateralId] == 0) {
            info.active.exclude(collateralId);
        }
    }

    function getAllDepositAccountMarketValue(Info storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256)
    {
        int256 accountMarketValue;
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 collateralId = set.active[i];

            if (collateralId == 0) break;
            IClearingHouseStructures.Collateral storage collateral = protocol.collaterals[collateralId];

            accountMarketValue += set.deposits[collateralId].toInt256().mulDiv(
                collateral.settings.oracle.getTwapPriceX128(collateral.settings.twapDuration),
                FixedPoint128.Q128
            );
        }
        return accountMarketValue;
    }

    function getInfo(Info storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (IClearingHouseStructures.DepositTokenView[] memory depositTokens)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        depositTokens = new IClearingHouseStructures.DepositTokenView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            depositTokens[i].cTokenAddress = address(protocol.collaterals[set.active[i]].token);
            depositTokens[i].balance = set.deposits[set.active[i]];
        }
    }
}
