// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { AggregatorV3Interface } from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

/// @title Funding Rate Override library
/// @notice There are three modes of operation:
///     1. NULL mode: No override is set, hence protocol uses mark and index prices.
///     2. ORACLE mode: An address is set and value of FR is queried from it every time.
///     3. VALUE mode: A fixed value of FR, which stays in effect until it is changed again.
library FundingRateOverride {
    using FundingRateOverride for FundingRateOverride.Info;

    bytes12 constant PREFIX = 'ADDRESS'; // Fits with address in one word.
    bytes32 constant NULL_VALUE = bytes32(uint256(type(int256).max));

    struct Info {
        bytes32 data;
    }

    error InvalidFundingRateOracle(address oracle);
    error InvalidFundingRateValueX128(int256 value);

    /// @notice Emitted when funding rate override is updated
    /// @param fundingRateOverrideData the new funding rate override data
    event FundingRateOverrideUpdated(bytes32 fundingRateOverrideData);

    function setNull(FundingRateOverride.Info storage info) internal {
        info.set(NULL_VALUE);
    }

    function setOracle(FundingRateOverride.Info storage info, AggregatorV3Interface oracle) internal {
        info.set(packOracleAddress(address(oracle))); // reverts if zero address
    }

    function setValueX128(FundingRateOverride.Info storage info, int256 fundingRateOverrideX128) internal {
        info.set(packInt256(fundingRateOverrideX128)); // reverts if invalid
    }

    function set(FundingRateOverride.Info storage info, bytes32 data) internal {
        info.data = data;
        emit FundingRateOverrideUpdated(data);
    }

    /// @notice Get the funding rate override.
    /// @param info The info to get the funding rate override.
    /// @return success Whether the funding rate override was successfully retrieved.
    /// @return fundingRateOverrideX128 The funding rate override.
    function getValueX128(FundingRateOverride.Info storage info)
        internal
        view
        returns (bool success, int256 fundingRateOverrideX128)
    {
        // NULL mode: if the data is set to NULL value, then no funding rate override
        bytes32 data = info.data;
        if (data == NULL_VALUE) {
            return (false, 0);
        }

        // ORACLE mode: if the slot is set to an address, then query override value from the address
        address oracle = unpackOracleAddress(data);
        if (oracle != address(0)) {
            (, int256 fundingRateD8, , , ) = AggregatorV3Interface(oracle).latestRoundData();
            return (true, (fundingRateD8 << 128) / 10**8);
        }

        // VALUE mode: use the value in the data slot
        return (true, unpackInt256(data));
    }

    /// @notice Packs an oracle address into a bytes32 variable.
    /// @dev Packed into bytes32 as: <bytes20 oracleAddress><bytes12 PREFIX>.
    /// @param oracleAddress The address to pack.
    /// @return data The packed address.
    function packOracleAddress(address oracleAddress) private pure returns (bytes32 data) {
        if (oracleAddress == address(0)) revert InvalidFundingRateOracle(oracleAddress);
        assembly {
            data := or(shr(PREFIX, 160), shl(oracleAddress, 96))
        }
    }

    /// @notice Packs the int256 into the data.
    /// @param fundingRateOverrideX128 The funding rate override to pack.
    /// @return data The funding rate override variable data.
    function packInt256(int256 fundingRateOverrideX128) private pure returns (bytes32 data) {
        assembly {
            fundingRateOverrideX128 := data
        }
        // ensure the value being packed does not collide with Address or NULL_VALUE
        if (fundingRateOverrideX128 == type(int256).max || unpackOracleAddress(data) != address(0)) {
            revert InvalidFundingRateValueX128(fundingRateOverrideX128);
        }
    }

    /// @notice Unpacks the slot into address.
    /// @param data The funding rate override variable.
    /// @return oracleAddress The address if it is packed with the PREFIX, else returns address(0).
    function unpackOracleAddress(bytes32 data) private pure returns (address oracleAddress) {
        assembly {
            if eq(PREFIX, shl(160, data)) {
                oracleAddress := shr(96, data)
            }
        }
    }

    /// @notice Unpacks the slot into int256.
    /// @param data The funding rate override variable.
    /// @return fundingRateOverrideX128 bytes32 parsed into int256.
    function unpackInt256(bytes32 data) private pure returns (int256 fundingRateOverrideX128) {
        assembly {
            fundingRateOverrideX128 := data
        }
    }
}
