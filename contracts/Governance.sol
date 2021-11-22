//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { Governable } from './utils/Governable.sol';

abstract contract Governance is Governable {
    mapping(address => bool) public supportedVTokens;
    mapping(address => bool) public supportedDeposits;
    uint256 public fixedFee;

    function updateSupportedVTokens(address add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedVTokens[add] = status;
    }

    function updateSupportedDeposits(address add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedDeposits[add] = status;
    }

    function updateFixedFee(uint256 _fixedFee) external onlyGovernanceOrTeamMultisig {
        fixedFee = _fixedFee;
    }
}
