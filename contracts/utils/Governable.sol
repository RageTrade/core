// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ContextUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { IGovernable } from '../interfaces/IGovernable.sol';

/// @title Governable module that exposes onlyGovernance and onlyGovernanceOrTeamMultisig modifiers
/// @notice Copied and modified from @openzeppelin/contracts/access/Ownable.sol
abstract contract Governable is IGovernable, Initializable, ContextUpgradeable {
    address private _governance;
    address private _teamMultisig;
    address private _governancePending;
    address private _teamMultisigPending;

    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);
    event TeamMultisigTransferred(address indexed previousTeamMultisig, address indexed newTeamMultisig);
    event GovernancePending(address indexed previousGovernancePending, address indexed newGovernancePending);
    event TeamMultisigPending(address indexed previousTeamMultisigPending, address indexed newTeamMultisigPending);

    error Unauthorised();
    error ZeroAddress();

    /// @notice Initializes the contract setting the deployer as the initial governance and team multisig.
    constructor() {
        __Governable_init();
    }

    /// @notice Useful to proxy contracts for initializing
    function __Governable_init() internal initializer {
        __Context_init();
        address msgSender = _msgSender();
        __Governable_init(msgSender, msgSender);
    }

    /// @notice Useful to proxy contracts for initializing with custom addresses
    /// @param initialGovernance the initial governance address
    /// @param initialTeamMultisig  the initial teamMultisig address
    function __Governable_init(address initialGovernance, address initialTeamMultisig) internal initializer {
        _governance = initialGovernance;
        emit GovernanceTransferred(address(0), initialGovernance);

        _teamMultisig = initialTeamMultisig;
        emit TeamMultisigTransferred(address(0), initialTeamMultisig);
    }

    /// @notice Returns the address of the current governance.

    function governance() public view virtual returns (address) {
        return _governance;
    }

    /// @notice Returns the address of the current governance.
    function governancePending() public view virtual returns (address) {
        return _governancePending;
    }

    /// @notice Returns the address of the current team multisig.transferTeamMultisig
    function teamMultisig() public view virtual returns (address) {
        return _teamMultisig;
    }

    /// @notice Returns the address of the current team multisig.transferTeamMultisig
    function teamMultisigPending() public view virtual returns (address) {
        return _teamMultisigPending;
    }

    /// @notice Throws if called by any account other than the governance.
    modifier onlyGovernance() {
        if (governance() != _msgSender()) revert Unauthorised();
        _;
    }

    /// @notice Throws if called by any account other than the governance or team multisig.
    modifier onlyGovernanceOrTeamMultisig() {
        if (teamMultisig() != _msgSender() && governance() != _msgSender()) revert Unauthorised();
        _;
    }

    /// @notice Initiates governance transfer to a new account (`newGovernancePending`).
    /// @param newGovernancePending the new governance address
    function initiateGovernanceTransfer(address newGovernancePending) external virtual onlyGovernance {
        _ensureNonZero(newGovernancePending);

        emit GovernancePending(_governancePending, newGovernancePending);
        _governancePending = newGovernancePending;
    }

    /// @notice Completes governance transfer, on being called by _governancePending.
    function acceptGovernanceTransfer() external virtual {
        if (_msgSender() != _governancePending) revert Unauthorised();

        emit GovernanceTransferred(_governance, _governancePending);
        _governance = _governancePending;
        _governancePending = address(0);
    }

    /// @notice Initiates teamMultisig transfer to a new account (`newTeamMultisigPending`).
    /// @param newTeamMultisigPending the new team multisig address
    function initiateTeamMultisigTransfer(address newTeamMultisigPending) external virtual onlyGovernance {
        _ensureNonZero(newTeamMultisigPending);

        emit TeamMultisigPending(_teamMultisigPending, newTeamMultisigPending);
        _teamMultisigPending = newTeamMultisigPending;
    }

    /// @notice Completes teamMultisig transfer, on being called by _teamMultisigPending.
    function acceptTeamMultisigTransfer() external virtual {
        if (_msgSender() != _teamMultisigPending) revert Unauthorised();

        emit TeamMultisigTransferred(_teamMultisig, _teamMultisigPending);
        _teamMultisig = _teamMultisigPending;
        _teamMultisigPending = address(0);
    }

    /// @notice Ensures that the passed value is not zero address
    /// @param value the value to check
    function _ensureNonZero(address value) private pure {
        if (value == address(0)) revert ZeroAddress();
    }
}
