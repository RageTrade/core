//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { VBASE_ADDRESS } from '../Constants.sol';
import { VTokenPosition } from './VTokenPosition.sol';
import { FullMath } from './FullMath.sol';
import { Uint32L8ArrayLib } from './Uint32L8Array.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';

library DepositTokenSet {
    using VTokenLib for VTokenAddress;
    using Uint32L8ArrayLib for uint32[8];
    int256 internal constant Q96 = 0x1000000000000000000000000;

    struct Info {
        // fixed length array of truncate(tokenAddress)
        // open positions in 8 different pairs at same time.
        // single per pool because it's fungible, allows for having
        uint32[8] active;
        mapping(uint32 => uint256) deposits;
    }

    // add overrides that accept vToken or truncated
    // TODO remove return val if it is not useful
    function increaseBalance(
        Info storage info,
        address vTokenAddress,
        uint256 amount
    ) internal {
        // consider vbase as always active because it is base (actives are needed for margin check)
        if (vTokenAddress != VBASE_ADDRESS) {
            info.active.include(truncate(vTokenAddress));
        }
        info.deposits[truncate(vTokenAddress)] += amount;
    }

    function decreaseBalance(
        Info storage info,
        address vTokenAddress,
        uint256 amount
    ) internal {
        // consider vbase as always active because it is base (actives are needed for margin check)
        if (vTokenAddress != VBASE_ADDRESS) {
            info.active.include(truncate(vTokenAddress));
        }

        require(info.deposits[truncate(vTokenAddress)] >= amount);
        info.deposits[truncate(vTokenAddress)] -= amount;
    }

    function truncate(address _add) internal pure returns (uint32) {
        return uint32(uint160(_add));
    }

    function getAllDepositAccountMarketValue(Info storage set, mapping(uint32 => address) storage vTokenAddresses)
        internal
        view
        returns (int256)
    {
        int256 accountMarketValue;
        for (uint8 i = 0; i < set.active.length; i++) {
            uint32 truncated = set.active[i];

            if (truncated == 0) break;
            VTokenAddress vToken = VTokenAddress.wrap(vTokenAddresses[truncated]);

            accountMarketValue += int256(set.deposits[truncated] * vToken.getRealTwapPrice());
        }

        accountMarketValue += int256(set.deposits[truncate(VBASE_ADDRESS)]);

        return accountMarketValue;
    }
}