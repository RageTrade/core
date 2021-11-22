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

    constructor(address VPoolFactory_) {
        VPoolFactory = VPoolFactory_;
    }

    function isKeyAvailable(uint32 _key) external view returns (bool) {
        if (vTokenAddresses[_key] == address(0)) return true;
        else return false;
    }

    function isRealTokenAlreadyInitilized(address _realToken) external view returns (bool) {
        return realTokenInitilized[_realToken];
    }

    function addKey(uint32 _key, address _add) external onlyVPoolFactory {
        vTokenAddresses[_key] = _add;
    }

    function initRealToken(address _realToken) external onlyVPoolFactory {
        realTokenInitilized[_realToken] = true;
    }

    function setConstants(Constants memory _constants) external onlyVPoolFactory {
        constants = _constants;
    }

    modifier onlyVPoolFactory() {
        if (VPoolFactory != msg.sender) revert NotVPoolFactory();
        _;
    }
}
