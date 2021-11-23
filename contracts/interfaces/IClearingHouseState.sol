//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { Constants } from '../utils/Constants.sol';

interface IClearingHouseState {
    function isKeyAvailable(uint32 _key) external view returns (bool);

    function addKey(uint32 _key, address _add) external;

    function isRealTokenAlreadyInitilized(address _realToken) external view returns (bool);

    function initRealToken(address _realToken) external;

    function setConstants(Constants memory constants) external;
}
