//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Constants } from '../Constants.sol';

interface IVPoolFactory {
    function parameters()
        external
        view
        returns (
            address vTokenAddress,
            uint16 initialMargin,
            uint16 maintainanceMargin,
            uint32 twapDuration,
            Constants memory constants
        );
}
