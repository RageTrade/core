//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

contract OptimisticGasUsedClaim {
    error ExcessGasUsedClaim(uint256 gasUsedClaim, uint256 gasUsedActual);

    modifier checkGasUsedClaim(uint256 gasUsedClaim) {
        if (gasUsedClaim > 0) {
            uint256 initialGas = gasleft();
            _;
            uint256 gasUsedActual = gasleft() - initialGas;
            if (gasUsedClaim > gasUsedActual) {
                revert ExcessGasUsedClaim(gasUsedClaim, gasUsedActual);
            }
        } else {
            _;
        }
    }
}