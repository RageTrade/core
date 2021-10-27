//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IVToken {
    function realToken() external view returns (address);

    function oracle() external view returns (address);
}
