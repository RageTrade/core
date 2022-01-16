//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Account } from '../../libraries/Account.sol';
import { VTokenAddress, VTokenLib } from '../../libraries/VTokenLib.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IVBase } from '../../interfaces/IVBase.sol';

abstract contract AccountProtocolInfoMock {
    using VTokenLib for VTokenAddress;

    Account.ProtocolInfo public protocol;

    uint256 public fixFee;

    function setAccountStorage(
        Account.LiquidationParams calldata _liquidationParams,
        uint256 _minRequiredMargin,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _fixFee
    ) external {
        protocol.liquidationParams = _liquidationParams;
        protocol.minRequiredMargin = _minRequiredMargin;
        protocol.removeLimitOrderFee = _removeLimitOrderFee;
        protocol.minimumOrderNotional = _minimumOrderNotional;
        fixFee = _fixFee;
    }

    function registerPool(address full, IClearingHouse.RageTradePool calldata rageTradePool) external virtual {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(protocol.vTokenAddresses[truncated].eq(address(0)));

        protocol.vTokenAddresses[truncated] = vTokenAddress;
        protocol.pools[vTokenAddress] = rageTradePool;
    }

    function setVBaseAddress(IVBase _vBase) external {
        protocol.vBase = _vBase;
    }
}
