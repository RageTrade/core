//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Constants } from '../utils/Constants.sol';

interface IVPoolWrapperDeployer {
    function parameters()
        external
        view
        returns (
            address vTokenAddress,
            address vPoolAddress,
            uint24 extendedLpFee,
            uint24 protocolFee,
            uint16 initialMargin,
            uint16 maintainanceMargin,
            uint32 twapDuration,
            Constants memory constants
        );

    function byteCodeHash() external pure returns (bytes32);

    function deployVPoolWrapper(
        address vTokenAddress,
        address vPool,
        uint24 extendedLpFee,
        uint24 protocolFee,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration,
        Constants memory constants
    ) external returns (address);
}
