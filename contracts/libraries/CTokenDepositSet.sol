//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from './Account.sol';
import { CTokenLib } from './CTokenLib.sol';
import { SignedFullMath } from './SignedFullMath.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';

import { IClearingHouse } from '../interfaces/IClearingHouse.sol';

import { console } from 'hardhat/console.sol';

library CTokenDepositSet {
    using CTokenLib for CTokenLib.CToken;
    using CTokenLib for address;
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
        address realTokenAddress,
        uint256 amount
    ) internal {
        uint32 truncated = realTokenAddress.truncate();

        // consider vbase as always active because it is base (actives are needed for margin check)
        info.active.include(truncated);

        info.deposits[realTokenAddress.truncate()] += amount;
    }

    function decreaseBalance(
        Info storage info,
        address realTokenAddress,
        uint256 amount
    ) internal {
        uint32 truncated = realTokenAddress.truncate();

        require(info.deposits[truncated] >= amount);
        info.deposits[truncated] -= amount;

        if (info.deposits[truncated] == 0) {
            info.active.exclude(truncated);
        }
    }

    function getAllDepositAccountMarketValue(Info storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (int256)
    {
        int256 accountMarketValue;
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];

            if (truncated == 0) break;
            CTokenLib.CToken storage token = protocol.rTokens[truncated];

            accountMarketValue += set.deposits[truncated].toInt256().mulDiv(
                token.getRealTwapPriceX128(),
                FixedPoint128.Q128
            );
        }
        return accountMarketValue;
    }

    function getView(Info storage set, Account.ProtocolInfo storage protocol)
        internal
        view
        returns (IClearingHouse.DepositTokenView[] memory depositTokens)
    {
        uint256 numberOfTokenPositions = set.active.numberOfNonZeroElements();
        depositTokens = new IClearingHouse.DepositTokenView[](numberOfTokenPositions);

        for (uint256 i = 0; i < numberOfTokenPositions; i++) {
            depositTokens[i].rTokenAddress = address(protocol.rTokens[set.active[i]].tokenAddress);
            depositTokens[i].balance = set.deposits[set.active[i]];
        }
    }
}
