//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { Account } from '../../libraries/Account.sol';
import { IVToken } from '../../libraries/VTokenLib.sol';

import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IOracle } from '../../interfaces/IOracle.sol';

import { Governable } from '../../utils/Governable.sol';

abstract contract ClearingHouseStorage is Initializable, Governable {
    // 2 slots are consumed from inheritance
    // rest slots reserved for any states from inheritance in future
    uint256[98] private _emptySlots1;

    // at slot # 100
    Account.ProtocolInfo internal protocol;

    mapping(IVToken => bool) public supportedVTokens;
    mapping(address => bool) public supportedDeposits;

    uint256 public numAccounts;
    mapping(uint256 => Account.UserInfo) accounts;

    // TODO use openzeppelin pauser
    bool public paused;

    IERC20 public rBase;
    address public rageTradeFactoryAddress;
    IInsuranceFund public insuranceFund;

    // Oracle for the chain's native currency in terms of rBase
    // Used to provide gas refund in rBase to the liquidators
    IOracle public nativeOracle;

    // reserved for adding slots in future
    uint256[100] private _emptySlots2;
}
