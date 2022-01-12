//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Constants } from '../../utils/Constants.sol';
import { IVPoolWrapperDeployer } from '../../interfaces/IVPoolWrapperDeployer.sol';
import { VPoolWrapperMockRealistic } from './VPoolWrapperMockRealistic.sol';

// import { VPoolWrapperDeployer } from '../../VPoolWrapperDeployer.sol';

// contract VPoolWrapperDeployerMockRealistic is VPoolWrapperDeployer {
//     constructor(address _VPoolFactory) VPoolWrapperDeployer(_VPoolFactory) {}

//     function deployVPoolWrapper(
//         address vTokenAddress,
//         address vPoolAddress,
//         address oracleAddress,
//         uint24 extendedLpFee,
//         uint24 protocolFee,
//         uint16 initialMargin,
//         uint16 maintainanceMargin,
//         uint32 twapDuration,
//         bool whitelisted,
//         Constants memory constants
//     ) external override returns (address) {
//         bytes32 salt = keccak256(abi.encode(vTokenAddress, constants.VBASE_ADDRESS));
//         bytes memory bytecode = type(VPoolWrapperMockRealistic).creationCode;
//         parameters = Parameters(
//             vTokenAddress,
//             vPoolAddress,
//             oracleAddress,
//             extendedLpFee,
//             protocolFee,
//             initialMargin,
//             maintainanceMargin,
//             twapDuration,
//             whitelisted,
//             constants
//         );
//         address deployedAddress = Create2.deploy(0, salt, bytecode);
//         delete parameters;
//         return deployedAddress;
//     }
// }
