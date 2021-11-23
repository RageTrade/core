//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { IClearingHouseState } from './interfaces/IClearingHouseState.sol';
import { Constants } from './utils/Constants.sol';
import { Governable } from './utils/Governable.sol';

abstract contract ClearingHouseState is IClearingHouseState, Governable {
    address public VPoolFactory;
    Constants public constants;

    mapping(uint32 => address) vTokenAddresses;
    mapping(address => bool) public realTokenInitilized;
    mapping(address => bool) public supportedVTokens;
    mapping(address => bool) public supportedDeposits;
    uint256 public fixedFee;

    error NotVPoolFactory();

    constructor(address _VPoolFactory) {
        VPoolFactory = _VPoolFactory;
    }

    function isKeyAvailable(uint32 key) external view returns (bool) {
        if (vTokenAddresses[key] == address(0)) return true;
        else return false;
    }

    function isRealTokenAlreadyInitilized(address realToken) external view returns (bool) {
        return realTokenInitilized[realToken];
    }

    function addKey(uint32 key, address add) external onlyVPoolFactory {
        vTokenAddresses[key] = add;
    }

    function initRealToken(address realToken) external onlyVPoolFactory {
        realTokenInitilized[realToken] = true;
    }

    function setConstants(Constants memory _constants) external onlyVPoolFactory {
        constants = _constants;
    }

    function updateSupportedVTokens(address add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedVTokens[add] = status;
    }

    function updateSupportedDeposits(address add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedDeposits[add] = status;
    }

    function updateFixedFee(uint256 _fixedFee) external onlyGovernanceOrTeamMultisig {
        fixedFee = _fixedFee;
    }

    modifier onlyVPoolFactory() {
        if (VPoolFactory != msg.sender) revert NotVPoolFactory();
        _;
    }
}
