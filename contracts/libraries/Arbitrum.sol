//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Calldata } from './Calldata.sol';

import { ArbAggregator } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbAggregator.sol';
import { ArbSys } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbSys.sol';
import { ArbGasInfo } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbGasInfo.sol';

library Arbitrum {
    ArbAggregator constant arbAggregator = ArbAggregator(0x000000000000000000000000000000000000006D);
    ArbSys constant arbSys = ArbSys(0x0000000000000000000000000000000000000064);
    ArbGasInfo constant arbGasInfo = ArbGasInfo(0x000000000000000000000000000000000000006C);

    function getStorageGasAvailable() internal view returns (uint256) {
        (bool success, bytes memory data) = address(arbSys).staticcall(
            abi.encodeCall(arbSys.getStorageGasAvailable, ())
        );
        if (!success || data.length == 0) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function getCurrentTxL1GasFees() internal view returns (uint256) {
        (bool success, bytes memory data) = address(arbSys).staticcall(
            abi.encodeCall(arbGasInfo.getCurrentTxL1GasFees, ())
        );
        if (!success || data.length == 0) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function getTxGasPrice() internal view returns (uint256) {
        return tx.gasprice;
    }
}
