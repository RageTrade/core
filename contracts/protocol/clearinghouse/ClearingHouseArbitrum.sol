//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { ClearingHouse } from './ClearingHouse.sol';

import { Arbitrum } from '../../libraries/Arbitrum.sol';
import { PriceMath } from '../../libraries/PriceMath.sol';

contract ClearingHouseArbitrum is ClearingHouse {
    using FullMath for uint256;
    using PriceMath for uint160;

    function _getFixFee(uint256 l2ComputationUnits) internal view override returns (uint256 fixFee) {
        uint256 totalL1FeeInWei;

        // if call from EOA then include L1 fee, i.e. do not refund L1 fee to calls from contract
        // this is due to a single contract can make multiple liquidations in single tx.
        // TODO is there a way to refund L1 fee once to contracts?
        if (msg.sender == tx.origin) {
            totalL1FeeInWei = Arbitrum.getTotalL1FeeInWei();
        }

        // TODO put a upper limit to tx.gasprice
        uint256 l2ComputationFeeInWei = l2ComputationUnits * tx.gasprice;
        uint256 l2StorageFeeInWei; // TODO figure out this thing

        uint256 ethPriceInUsdc = nativeOracle.getTwapSqrtPriceX96(5 minutes).toPriceX128();
        return (totalL1FeeInWei + l2ComputationFeeInWei + l2StorageFeeInWei).mulDiv(ethPriceInUsdc, FixedPoint128.Q128);
    }
}
