//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Arbitrum } from '../libraries/Arbitrum.sol';

import { ClearingHouseArbitrum } from '../protocol/clearinghouse/ClearingHouseArbitrum.sol';

contract ArbitrumFixFeeTest is ClearingHouseArbitrum {
    function testMethod(uint256 claimGas) external checkGasUsedClaim(claimGas) {
        assembly {
            sstore(0x134dd30, 0x134dd30)
        }
    }

    event Uint(string str, uint256 val);

    function emitGasCostWei() external {
        emit Uint('Arbitrum.getTotalL1FeeInWei()', Arbitrum.getCurrentTxL1GasFees());
    }

    // TODO remove this after arbitrum doubts are clear
    // https://discord.com/channels/585084330037084172/859511259183448084/929936482075050014

    // fallback() external {
    //     run();
    // }

    // function run() public {
    //     emit Arbitrum.Uint('gasleft()', gasleft());
    //     uint256 cost = Arbitrum.getCurrentTxL1GasFees();
    //     emit Arbitrum.Uint('gasleft()', gasleft());
    //     emit Arbitrum.Uint('cost', cost);
    //     emit Arbitrum.Uint('gasleft()', gasleft());
    //     uint256 l1fees = Arbitrum.arbGasInfo.getCurrentTxL1GasFees();
    //     emit Arbitrum.Uint('Arbitrum.arbGasInfo.getCurrentTxL1GasFees()', l1fees);
    //     emit Arbitrum.Uint('gasleft()', gasleft());

    //     address defaultAggregator = Arbitrum.arbAggregator.getDefaultAggregator();
    //     (uint256 intrinsicWei, uint256 weiPerCalldataUnits, , , , ) = Arbitrum.arbGasInfo.getPricesInWeiWithAggregator(
    //         defaultAggregator
    //     );

    //     emit Arbitrum.Uint(
    //         '(l1fees - intrinsicWei) / weiPerCalldataUnits',
    //         (l1fees - intrinsicWei) / weiPerCalldataUnits
    //     );
    // }

    // function trySstore() public {
    //     Arbitrum.printStuff();

    //     assembly {
    //         sstore(1, 2)
    //         sstore(3, 2)
    //     }

    //     Arbitrum.printStuff();
    // }

    // event Uint(string str, uint256 val);
    // event Address(string str, address val);
    // event Bytes(string str, bytes val);

    // function printStuff() internal {
    //     emit Uint('tx.gasprice', tx.gasprice);
    //     emit Uint('gasleft()', gasleft());
    //     address defaultAggregator = Arbitrum.arbAggregator.getDefaultAggregator();
    //     emit Address('getDefaultAggregator', defaultAggregator);
    //     emit Uint('getTxBaseFee', Arbitrum.arbAggregatorarbAggregator.getTxBaseFee(defaultAggregator));
    //     emit Uint('getStorageGasAvailable', Arbitrum.arbSys.getStorageGasAvailable()); // TODO this is always giving zero, check with arbitrum team
    //     {
    //         (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = Arbitrum
    //             .arbGasInfo
    //             .getPricesInWeiWithAggregator(defaultAggregator);
    //         emit Uint('getPricesInWeiWithAggregator-a', a); // this is L1 fixed fee exactly
    //         emit Uint('getPricesInWeiWithAggregator-b', b); // need to take this and multiply with calldata units
    //         emit Uint('getPricesInWeiWithAggregator-c', c); // per storage slot
    //         emit Uint('getPricesInWeiWithAggregator-d', d);
    //         emit Uint('getPricesInWeiWithAggregator-e', e);
    //         emit Uint('getPricesInWeiWithAggregator-f', f);
    //     }

    //     {
    //         (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f) = Arbitrum.arbGasInfo.getPricesInWei();
    //         emit Uint('getPricesInWei-a', a);
    //         emit Uint('getPricesInWei-b', b);
    //         emit Uint('getPricesInWei-c', c);
    //         emit Uint('getPricesInWei-d', d);
    //         emit Uint('getPricesInWei-e', e);
    //         emit Uint('getPricesInWei-f', f);
    //     }

    //     {
    //         (uint256 a, uint256 b, uint256 c) = Arbitrum.arbGasInfo.getPricesInArbGasWithAggregator(defaultAggregator);
    //         emit Uint('getPricesInArbGasWithAggregator-a', a);
    //         emit Uint('getPricesInArbGasWithAggregator-b', b);
    //         emit Uint('getPricesInArbGasWithAggregator-c', c);
    //     }
    //     {
    //         (uint256 a, uint256 b, uint256 c) = Arbitrum.arbGasInfo.getPricesInArbGas();
    //         emit Uint('getPricesInArbGas-a', a);
    //         emit Uint('getPricesInArbGas-b', b);
    //         emit Uint('getPricesInArbGas-c', c);
    //     }

    //     {
    //         (uint256 a, uint256 b, uint256 c) = Arbitrum.arbGasInfo.getGasAccountingParams();
    //         emit Uint('getGasAccountingParams-a', a);
    //         emit Uint('getGasAccountingParams-b', b);
    //         emit Uint('getGasAccountingParams-c', c);
    //     }

    //     emit Uint('getL1GasPriceEstimate', Arbitrum.arbGasInfo.getL1GasPriceEstimate());
    //     emit Uint('getCurrentTxL1GasFees', Arbitrum.arbGasInfo.getCurrentTxL1GasFees());
    //     emit Uint('gasleft()', gasleft());
    // }
}
