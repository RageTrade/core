// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { Governable } from './Governable.sol';

abstract contract TxGasPriceLimit is Governable {
    uint256 public txGasPriceLimit;

    error ExcessTxGasPrice(uint256 txGasPrice, uint256 limit);

    modifier checkTxGasPrice(uint256 txGasPrice) {
        if (txGasPrice > txGasPriceLimit) {
            revert ExcessTxGasPrice(txGasPrice, txGasPriceLimit);
        }
        _;
    }

    function setTxGasPriceLimit(uint256 _txGasPriceLimit) external onlyGovernanceOrTeamMultisig {
        txGasPriceLimit = _txGasPriceLimit;
    }
}
