// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { Account } from '../../libraries/Account.sol';
import { BatchedLoop } from '../../libraries/BatchedLoop.sol';
import { Protocol } from '../../libraries/Protocol.sol';

import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IOracle } from '../../interfaces/IOracle.sol';

abstract contract ClearingHouseStorage {
    // rest slots reserved for any states from inheritance in future
    uint256[100] private _emptySlots1;

    // at slot # 100
    Protocol.Info internal protocol;

    uint256 public numAccounts;
    mapping(uint256 => Account.Info) accounts;

    address public rageTradeFactoryAddress;
    IInsuranceFund public insuranceFund;

    // progress index, used for performing for loop
    // over an unbounded array in multiple txs
    BatchedLoop.Info internal pauseLoop;
    BatchedLoop.Info internal unpauseLoop;
    BatchedLoop.Info internal withdrawProtocolFeeLoop;

    // reserved for adding slots in future
    uint256[100] private _emptySlots2;
}
