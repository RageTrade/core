//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { AccountStorage, LiquidationParams } from '../../libraries/Account.sol';
import { VTokenAddress, VTokenLib } from '../../libraries/VTokenLib.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';

abstract contract AccountStorageMock {
    using VTokenLib for VTokenAddress;

    AccountStorage public accountStorage;

    uint256 public fixFee;

    function setAccountStorage(
        LiquidationParams calldata _liquidationParams,
        uint256 _minRequiredMargin,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _fixFee
    ) external {
        accountStorage.liquidationParams = _liquidationParams;
        accountStorage.minRequiredMargin = _minRequiredMargin;
        accountStorage.removeLimitOrderFee = _removeLimitOrderFee;
        accountStorage.minimumOrderNotional = _minimumOrderNotional;
        fixFee = _fixFee;
    }

    function registerPool(address full, IClearingHouse.RageTradePool calldata rageTradePool) external virtual {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(accountStorage.vTokenAddresses[truncated].eq(address(0)));

        accountStorage.vTokenAddresses[truncated] = vTokenAddress;
        accountStorage.rtPools[vTokenAddress] = rageTradePool;
    }

    function setVBaseAddress(address VBASE_ADDRESS) external {
        accountStorage.VBASE_ADDRESS = VBASE_ADDRESS;
    }
}
