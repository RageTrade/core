//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Constants } from './utils/Constants.sol';
import { IVPoolWrapperDeployer } from './interfaces/IVPoolWrapperDeployer.sol';
import { VPoolWrapper } from './VPoolWrapper.sol';

contract VPoolWrapperDeployer is IVPoolWrapperDeployer {
    error NotVPoolFactory();

    struct Parameters {
        address vTokenAddress;
        address vPoolAddress;
        uint24 extendedLpFee;
        uint24 protocolFee;
        uint16 initialMargin;
        uint16 maintainanceMargin;
        uint32 twapDuration;
        bool whitelisted;
        Constants constants;
    }
    Parameters public override parameters;
    address public immutable VPoolFactory;

    constructor(address _VPoolFactory) {
        VPoolFactory = _VPoolFactory;
    }

    function deployVPoolWrapper(
        address vTokenAddress,
        address vPool,
        uint24 extendedLpFee,
        uint24 protocolFee,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration,
        bool whitelisted,
        Constants memory constants
    ) external returns (address) {
        if (msg.sender != VPoolFactory) revert NotVPoolFactory();
        bytes32 salt = keccak256(abi.encode(vTokenAddress, constants.VBASE_ADDRESS));
        bytes memory bytecode = type(VPoolWrapper).creationCode;
        parameters = Parameters(
            vTokenAddress,
            vPool,
            extendedLpFee,
            protocolFee,
            initialMargin,
            maintainanceMargin,
            twapDuration,
            whitelisted,
            constants
        );
        address deployedAddress = Create2.deploy(0, salt, bytecode);
        delete parameters;
        return deployedAddress;
    }

    function byteCodeHash() external pure returns (bytes32) {
        return keccak256(type(VPoolWrapper).creationCode);
    }
}
