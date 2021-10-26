//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IVPoolFactory {
    function parameters()
        external
        view
        returns (
            uint16 initialMargin,
            uint16 maintainanceMargin,
            uint32 twapDuration
        );
}
