//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Calldata } from './Calldata.sol';

import { ArbAggregator } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbAggregator.sol';
import { ArbSys } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbSys.sol';
import { ArbGasInfo } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbGasInfo.sol';

import { console } from 'hardhat/console.sol';

library Arbitrum {
    ArbAggregator constant arbAggregator = ArbAggregator(0x000000000000000000000000000000000000006D);
    ArbSys constant arbSys = ArbSys(0x0000000000000000000000000000000000000064);
    ArbGasInfo constant arbGasInfo = ArbGasInfo(0x000000000000000000000000000000000000006C);

    function getGasCostWei() internal view returns (uint256) {
        return arbGasInfo.getCurrentTxL1GasFees();

        // uint256 calldataUnits = Calldata.calculateCostUnits(data);
        // address defaultAggregator = arbAggregator.getDefaultAggregator();
        // (uint256 intrinsicWei, uint256 weiPerCalldataUnits, , , , ) = arbGasInfo.getPricesInWeiWithAggregator(
        //     defaultAggregator
        // );
        // emit Uint('calldataUnits', calldataUnits);
        // emit Uint('weiPerCalldataUnits', weiPerCalldataUnits);
        // emit Bytes('data', data);
        // return intrinsicWei + calldataUnits * weiPerCalldataUnits;
    }

    // TODO remove this after arbitrum doubts are clear
    // https://discord.com/channels/585084330037084172/859511259183448084/929936482075050014

    event Uint(string str, uint256 val);
    event Address(string str, address val);
    event Bytes(string str, bytes val);

    function printStuff() internal {
        address defaultAggregator = arbAggregator.getDefaultAggregator();
        emit Address('getDefaultAggregator', defaultAggregator);
        emit Uint('getTxBaseFee', arbAggregator.getTxBaseFee(defaultAggregator));
        emit Uint('getStorageGasAvailable', arbSys.getStorageGasAvailable()); // TODO this is always giving zero, check with arbitrum team
        {
            (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = arbGasInfo
                .getPricesInWeiWithAggregator(defaultAggregator);
            emit Uint('getPricesInWeiWithAggregator-a', a); // this is L1 fixed fee exactly
            emit Uint('getPricesInWeiWithAggregator-b', b); // need to take this and multiply with calldata units
            emit Uint('getPricesInWeiWithAggregator-c', c); // per storage slot
            emit Uint('getPricesInWeiWithAggregator-d', d);
            emit Uint('getPricesInWeiWithAggregator-e', e);
            emit Uint('getPricesInWeiWithAggregator-f', f);
        }

        {
            (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = arbGasInfo.getPricesInWei();
            emit Uint('getPricesInWei-a', a);
            emit Uint('getPricesInWei-b', b);
            emit Uint('getPricesInWei-c', c);
            emit Uint('getPricesInWei-d', d);
            emit Uint('getPricesInWei-e', e);
            emit Uint('getPricesInWei-f', f);
        }

        {
            (uint256 a, uint256 b, uint256 c) = arbGasInfo.getPricesInArbGasWithAggregator(defaultAggregator);
            emit Uint('getPricesInArbGasWithAggregator-a', a);
            emit Uint('getPricesInArbGasWithAggregator-b', b);
            emit Uint('getPricesInArbGasWithAggregator-c', c);
        }
        {
            (uint256 a, uint256 b, uint256 c) = arbGasInfo.getPricesInArbGas();
            emit Uint('getPricesInArbGas-a', a);
            emit Uint('getPricesInArbGas-b', b);
            emit Uint('getPricesInArbGas-c', c);
        }

        {
            (uint256 a, uint256 b, uint256 c) = arbGasInfo.getGasAccountingParams();
            emit Uint('getGasAccountingParams-a', a);
            emit Uint('getGasAccountingParams-b', b);
            emit Uint('getGasAccountingParams-c', c);
        }

        emit Uint('getL1GasPriceEstimate', arbGasInfo.getL1GasPriceEstimate());
        emit Uint('getCurrentTxL1GasFees', arbGasInfo.getCurrentTxL1GasFees());
    }
}
