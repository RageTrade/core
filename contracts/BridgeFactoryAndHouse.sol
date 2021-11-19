//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { IBridgeFactoryAndHouse } from './interfaces/IBridgeFactoryAndHouse.sol';

abstract contract BridgeFactoryAndHouse is IBridgeFactoryAndHouse {
    address public VPoolFactory;

    mapping(uint32 => address) vTokenAddresses;
    mapping(address => bool) public realTokenInitilized;

    error Unauthorised();

    constructor(address VPoolFactory_) {
        VPoolFactory = VPoolFactory_;
    }

    function isKeyAvailable(uint32 _key) external view returns (bool) {
        if (vTokenAddresses[_key] == address(0)) return true;
        else return false;
    }

    function addKey(uint32 _key, address _add) external {
        if (VPoolFactory != msg.sender) revert Unauthorised();
        vTokenAddresses[_key] = _add;
    }

    function isRealTokenAlreadyInitilized(address _realToken) external view returns (bool) {
        return realTokenInitilized[_realToken];
    }

    function initRealToken(address _realToken) external {
        if (VPoolFactory != msg.sender) revert Unauthorised();
        realTokenInitilized[_realToken] = true;
    }
}
