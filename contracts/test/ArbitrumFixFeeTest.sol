//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Arbitrum } from '../libraries/Arbitrum.sol';

contract ArbitrumFixFeeTest {
    event Uint(string str, uint256 val);

    function emitGasCostWei() external {
        emit Uint('Arbitrum.getTotalL1FeeInWei()', Arbitrum.getTotalL1FeeInWei());
        emit Uint('tx.gasprice', tx.gasprice);

        Arbitrum.printStuff();
    }

    // TODO remove this after arbitrum doubts are clear
    // https://discord.com/channels/585084330037084172/859511259183448084/929936482075050014

    fallback() external {
        run();
    }

    function run() public {
        emit Arbitrum.Uint('gasleft()', gasleft());
        uint256 cost = Arbitrum.getTotalL1FeeInWei();
        emit Arbitrum.Uint('gasleft()', gasleft());
        emit Arbitrum.Uint('cost', cost);
        emit Arbitrum.Uint('gasleft()', gasleft());
        uint256 l1fees = Arbitrum.arbGasInfo.getCurrentTxL1GasFees();
        emit Arbitrum.Uint('Arbitrum.arbGasInfo.getCurrentTxL1GasFees()', l1fees);
        emit Arbitrum.Uint('gasleft()', gasleft());

        address defaultAggregator = Arbitrum.arbAggregator.getDefaultAggregator();
        (uint256 intrinsicWei, uint256 weiPerCalldataUnits, , , , ) = Arbitrum.arbGasInfo.getPricesInWeiWithAggregator(
            defaultAggregator
        );

        emit Arbitrum.Uint(
            '(l1fees - intrinsicWei) / weiPerCalldataUnits',
            (l1fees - intrinsicWei) / weiPerCalldataUnits
        );
    }

    function trySstore() public {
        Arbitrum.printStuff();

        assembly {
            sstore(1, 2)
            sstore(3, 2)
        }

        Arbitrum.printStuff();
    }
}
