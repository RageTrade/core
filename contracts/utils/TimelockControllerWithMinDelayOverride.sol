// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { TimelockController } from '@openzeppelin/contracts/governance/TimelockController.sol';

/// @title Timelock controller with a minimum delay override for certain functions
contract TimelockControllerWithMinDelayOverride is TimelockController {
    uint256 private _minDelayOverridePlusOne;
    mapping(bytes32 => uint256) public minDelayOverridesPlusOne;

    event MinDelayOverrideChange(address target, bytes4 selector, uint256 newMinDelay);

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}

    function setMinDelayOverride(
        address target,
        bytes4 selector,
        uint256 minDelayOverride
    ) public {
        require(msg.sender == address(this), 'TimelockController: caller must be timelock');
        minDelayOverridesPlusOne[getKey(target, selector)] = minDelayOverride + 1;
        emit MinDelayOverrideChange(target, selector, minDelayOverride);
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override onlyRole(PROPOSER_ROLE) {
        if (data.length >= 4) {
            uint256 minDelayOverridePlusOne = minDelayOverridesPlusOne[getKey(target, getSelectorFromData(data))];
            if (minDelayOverridePlusOne != 0) {
                _minDelayOverridePlusOne = minDelayOverridePlusOne; // SSTORE
            }
        }
        super.schedule(target, value, data, predecessor, salt, delay);
        delete _minDelayOverridePlusOne;
    }

    function getMinDelay() public view virtual override returns (uint256 duration) {
        uint256 minDelayOverridePlusOne = _minDelayOverridePlusOne;
        return minDelayOverridePlusOne == 0 ? super.getMinDelay() : minDelayOverridePlusOne - 1;
    }

    function getSelectorFromData(bytes calldata data) internal pure returns (bytes4 selector) {
        assembly {
            // clear first memory word
            mstore(0, 0)
            // copy calldata to memory scratch space
            calldatacopy(28, data.offset, 4)
            // load memory to stack
            selector := mload(0)
        }
    }

    function getKey(address target, bytes4 selector) public pure returns (bytes32 c) {
        assembly {
            // store a in the last 20 bytes and b in the 4 bytes before
            c := xor(target, shl(selector, 160))
        }
    }
}
