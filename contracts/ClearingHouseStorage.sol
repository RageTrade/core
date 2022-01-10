//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { Account } from './libraries/Account.sol';
import { Constants } from './utils/Constants.sol';
import { Governable } from './utils/Governable.sol';
import { LiquidationParams } from './libraries/Account.sol';
import { VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';
import { RealTokenLib } from './libraries/RealTokenLib.sol';

struct AccountStorage {
    Constants constants; // TODO make it immutable, involves seperating the constants, doing this might also cause stack too deep issues
    mapping(uint32 => VTokenAddress) vTokenAddresses;
    mapping(uint32 => RealTokenLib.RealToken) realTokens;
    LiquidationParams liquidationParams;
    uint256 minRequiredMargin;
    uint256 removeLimitOrderFee;
    uint256 minimumOrderNotional;
}

abstract contract ClearingHouseStorage is Governable {
    using VTokenLib for VTokenAddress;

    // changing immutables would require deploying a new implementation
    address public immutable vPoolFactory;
    address public immutable realBase;
    address public immutable insuranceFundAddress;

    mapping(address => bool) public realTokenInitilized;
    mapping(VTokenAddress => bool) public supportedVTokens;
    mapping(VTokenAddress => bool) public supportedDeposits;

    uint256 public numAccounts;
    mapping(uint256 => Account.Info) accounts;

    bool public paused;

    AccountStorage public accountStorage;

    error Paused();
    error NotVPoolFactory();

    // only initializes immutable vars
    constructor(
        address _vPoolFactory,
        address _realBase,
        address _insuranceFundAddress
    ) {
        vPoolFactory = _vPoolFactory;
        realBase = _realBase;
        insuranceFundAddress = _insuranceFundAddress;
    }
}
