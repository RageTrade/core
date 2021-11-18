//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IInsuranceFund {
    function claim(uint256 amount) external;
}
