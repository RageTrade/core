//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { IClearingHouseState } from './interfaces/IClearingHouseState.sol';
import { Constants } from './utils/Constants.sol';
import { Governable } from './utils/Governable.sol';
import { LiquidationParams } from './libraries/Account.sol';
import { VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';

abstract contract ClearingHouseState is IClearingHouseState, Governable {
    using VTokenLib for VTokenAddress;

    address public immutable VPoolFactory;

    mapping(uint32 => VTokenAddress) vTokenAddresses;
    mapping(address => bool) public realTokenInitilized;
    mapping(VTokenAddress => bool) public supportedVTokens;
    mapping(VTokenAddress => bool) public supportedDeposits;

    Constants public constants;
    LiquidationParams public liquidationParams;
    uint256 public removeLimitOrderFee;
    uint256 public minimumOrderNotional;

    error NotVPoolFactory();

    constructor(address _VPoolFactory) {
        VPoolFactory = _VPoolFactory;
    }

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool) {
        return vTokenAddresses[truncated].eq(address(0));
    }

    function isRealTokenAlreadyInitilized(address realToken) external view returns (bool) {
        return realTokenInitilized[realToken];
    }

    function addVTokenAddress(uint32 truncated, address full) external onlyVPoolFactory {
        vTokenAddresses[truncated] = VTokenAddress.wrap(full);
    }

    function initRealToken(address realToken) external onlyVPoolFactory {
        realTokenInitilized[realToken] = true;
    }

    function setConstants(Constants memory _constants) external onlyVPoolFactory {
        constants = _constants;
    }

    function updateSupportedVTokens(VTokenAddress add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedVTokens[add] = status;
    }

    function updateSupportedDeposits(VTokenAddress add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedDeposits[add] = status;
    }

    function setPlatformParameters(
        LiquidationParams calldata _liquidationParams,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional
    ) external onlyGovernanceOrTeamMultisig {
        liquidationParams = _liquidationParams;
        removeLimitOrderFee = _removeLimitOrderFee;
        minimumOrderNotional = _minimumOrderNotional;
    }

    modifier onlyVPoolFactory() {
        if (VPoolFactory != msg.sender) revert NotVPoolFactory();
        _;
    }
}
