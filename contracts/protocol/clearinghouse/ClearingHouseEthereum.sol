//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { FixedPoint128 } from '@uniswap/v3-core-0.8-support/contracts/libraries/FixedPoint128.sol';
import { FullMath } from '@uniswap/v3-core-0.8-support/contracts/libraries/FullMath.sol';

import { ClearingHouse } from './ClearingHouse.sol';

import { PriceMath } from '../../libraries/PriceMath.sol';
import { Calldata } from '../../libraries/Calldata.sol';

/// @notice ClearingHouse with gas fee refunds for liquidations on Ethereum L1 like chains
contract ClearingHouseEthereum is ClearingHouse {
    using FullMath for uint256;
    using PriceMath for uint160;

    function getFixFee(uint256 gasUnits) public view override returns (uint256 fixFee) {
        // incase user does not want refund, use zero
        if (gasUnits == 0) return 0;

        // if call from EOA then include intrinsic, i.e. does not refund intrinsic to calls from contract
        if (msg.sender == tx.origin) {
            gasUnits += 21000 + Calldata.calculateCostUnits(msg.data);
        }

        // TODO put a upper limit to tx.gasprice
        uint256 nativeAmount = tx.gasprice * gasUnits;
        uint256 nativePriceInRBase = nativeOracle.getTwapSqrtPriceX96(5 minutes).toPriceX128();
        return nativeAmount.mulDiv(nativePriceInRBase, FixedPoint128.Q128);
    }
}
