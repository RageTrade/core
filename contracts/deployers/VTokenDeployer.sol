//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';

import { GoodAddressDeployer } from '../libraries/GoodAddressDeployer.sol';

import { VToken, IVToken } from '../tokens/VToken.sol';

abstract contract VTokenDeployer {
    struct DeployVTokenParams {
        string vTokenName;
        string vTokenSymbol;
        address rTokenAddress; // TODO remove, not used
        address oracleAddress; // TODO move this to clearing house
    }

    /// @notice Deploys contract VToken at an address such that the last 4 bytes of contract address is unique
    /// @dev Use of CREATE2 is not to recompute address in future, but just to have unique last 4 bytes
    /// @param params: parameters used for construction, see above struct
    /// @return vToken : the deployed VToken contract
    function _deployVToken(DeployVTokenParams calldata params) internal returns (IVToken vToken) {
        bytes memory bytecode = abi.encodePacked(
            type(VToken).creationCode,
            abi.encode(
                params.vTokenName,
                params.vTokenSymbol,
                params.rTokenAddress,
                params.oracleAddress,
                address(this)
            )
        );

        vToken = IVToken(GoodAddressDeployer.deploy(0, bytecode, _isVTokenAddressGood));

        // TODO add this stuff in Pool Factory
        // clearingHouse.addVTokenAddress(truncated, vTokenAddressDeployed);
        // clearingHouse.initRealToken(setupVTokenParams.realTokenAddress);
    }

    // returns true if last 4 bytes are non-zero, also extended to add more conditions in VPoolFactory
    function _isVTokenAddressGood(address addr) internal pure virtual returns (bool) {
        return uint32(uint160(addr)) != 0;
    }

    // function _deployVToken(
    //     DeployVTokenParams calldata deployVTokenParams,
    //     uint256 salt,
    //     address vBaseAddress,
    //     function(uint32) returns (bool) isVTokenAddressAvailable
    // ) internal returns (address vTokenAddressDeployed) {
    //     unchecked {
    //         // TODO change require to custom errors
    //         // Pool for this token must not be already created

    //         // TODO add this check to VPoolFactory
    //         // require(!clearingHouse.isRealTokenAlreadyInitilized(setupVTokenParams.realTokenAddress), 'Duplicate Pool');

    //         bytes memory bytecode = abi.encodePacked(
    //             type(VToken).creationCode,
    //             abi.encode(
    //                 deployVTokenParams.vTokenName,
    //                 deployVTokenParams.vTokenSymbol,
    //                 deployVTokenParams.rTokenAddress,
    //                 deployVTokenParams.oracleAddress,
    //                 address(this)
    //             )
    //         );
    //         bytes32 byteCodeHash = keccak256(bytecode);
    //         // bytes32 salt;
    //         uint32 truncated;
    //         address vTokenAddressComputed;

    //         while (true) {
    //             vTokenAddressComputed = Create2.computeAddress(bytes32(salt), byteCodeHash);
    //             truncated = uint32(uint160(vTokenAddressComputed));
    //             if (
    //                 truncated != 0 &&
    //                 uint160(vTokenAddressComputed) < uint160(vBaseAddress) &&
    //                 isVTokenAddressAvailable(truncated)
    //             ) {
    //                 break;
    //             } else {
    //                 salt++; // using a different salt
    //             }
    //         }

    //         vTokenAddressDeployed = Create2.deploy(0, bytes32(salt), bytecode);
    //         assert(vTokenAddressComputed == vTokenAddressDeployed); // TODO disable in mainnet?

    //         // TODO add this stuff in Pool Factory
    //         // clearingHouse.addVTokenAddress(truncated, vTokenAddressDeployed);
    //         // clearingHouse.initRealToken(setupVTokenParams.realTokenAddress);
    //     }
    // }
}
