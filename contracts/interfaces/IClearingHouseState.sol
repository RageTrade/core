//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import { Constants } from '../utils/Constants.sol';

interface IClearingHouseState {
    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool);

    function addVTokenAddress(uint32 truncated, address full) external;

    function isRealTokenAlreadyInitilized(address _realToken) external view returns (bool);

    function initRealToken(address _realToken) external;

    function setConstants(Constants memory constants) external;
}
