//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { IBridgeFactoryAndHouse } from './interfaces/IBridgeFactoryAndHouse.sol';
import { Constants } from './utils/Constants.sol';

abstract contract BridgeFactoryAndHouse is IBridgeFactoryAndHouse {
    address public VPoolFactory;
    Constants public constants;

    mapping(uint32 => address) vTokenAddresses;
    mapping(address => bool) public realTokenInitilized;

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

    modifier onlyVPoolFactory() {
        if (VPoolFactory != msg.sender) revert NotVPoolFactory();
        _;
    }
}
