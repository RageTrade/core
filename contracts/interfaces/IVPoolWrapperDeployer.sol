//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Constants } from '../utils/Constants.sol';

interface IVPoolWrapperDeployer {
    function deployVPoolWrapper(
        address vTokenAddress,
        address vPoolAddress,
        address oracleAddress,
        uint24 extendedLpFee,
        uint24 protocolFee,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration,
        bool whitelisted,
        Constants memory constants
    ) external returns (address);
}
