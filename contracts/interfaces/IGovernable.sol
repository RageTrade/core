//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

interface IGovernable {
    function governance() external view returns (address);

    function teamMultisig() external view returns (address);

    function transferGovernance(address newGovernance) external;

    function transferTeamMultisig(address newTeamMultisig) external;
}
