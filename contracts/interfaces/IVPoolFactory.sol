//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Constants } from '../utils/Constants.sol';

interface IVPoolFactory {
    function parameters()
        external
        view
        returns (
            address vTokenAddress,
            address vPoolAddress,
            uint16 initialMargin,
            uint16 maintainanceMargin,
            uint32 twapDuration,
            Constants memory constants
        );
}
