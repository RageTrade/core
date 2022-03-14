// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import { ArbAggregator } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbAggregator.sol';
import { ArbSys } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbSys.sol';
import { ArbGasInfo } from '@134dd3v/arbos-precompiles/arbos/builtin/ArbGasInfo.sol';

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { Arbitrum } from '../../libraries/Arbitrum.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';

import { TxGasPriceLimit } from '../../utils/TxGasPriceLimit.sol';

import { ClearingHouse } from './ClearingHouse.sol';
import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract ClearingHouseArbitrum is ClearingHouse, TxGasPriceLimit {
    using AddressHelper for address;
    using FullMath for uint256;
    using PriceMath for uint160;

    modifier checkGasUsedClaim(uint256 l2GasUsedClaim) override {
        if (l2GasUsedClaim > 0) {
            // computation + storage
            uint256 initialL2Gas = gasleft() + Arbitrum.getStorageGasAvailable();
            _;
            uint256 l2GasUsedActual = initialL2Gas - (gasleft() + Arbitrum.getStorageGasAvailable());
            if (l2GasUsedClaim > l2GasUsedActual) {
                revert ExcessGasUsedClaim(l2GasUsedClaim, l2GasUsedActual);
            }
        } else {
            _;
        }
    }

    /// @notice Gives Fix Fee in Settlement Token denomination for the tx
    /// @param l2GasUnits: includes L2 computation and storage gas units
    function _getFixFee(uint256 l2GasUnits)
        internal
        view
        override
        checkTxGasPrice(tx.gasprice)
        returns (uint256 fixFee)
    {
        if (l2GasUnits == 0 || address(nativeOracle).isZero()) return 0;

        uint256 l1FeeInWei;

        // if call from EOA then include L1 fee, i.e. do not refund L1 fee to calls from contract
        // this is due to a single contract can make multiple liquidations in single tx.
        // TODO is there a way to refund L1 fee once to contracts?
        if (msg.sender == tx.origin) {
            l1FeeInWei = Arbitrum.getCurrentTxL1GasFees();
        }

        uint256 l2FeeInWei = l2GasUnits * tx.gasprice;

        uint256 ethPriceInUsdc = nativeOracle.getTwapPriceX128(5 minutes);
        return (l1FeeInWei + l2FeeInWei).mulDiv(ethPriceInUsdc, FixedPoint128.Q128);
    }
}
