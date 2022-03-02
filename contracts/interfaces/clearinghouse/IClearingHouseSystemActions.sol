//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IInsuranceFund } from '../IInsuranceFund.sol';
import { IOracle } from '../IOracle.sol';
import { IVBase } from '../IVBase.sol';
import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseSystemActions is IClearingHouseStructures {
    /// @notice initializes clearing house contract
    /// @param rageTradeFactoryAddress rage trade factory address
    /// @param defaultCollateralToken address of default collateral token
    /// @param defaultCollateralTokenOracle address of default collateral token oracle
    /// @param insuranceFund address of insurance fund
    /// @param vBase address of vBase
    /// @param nativeOracle address of native oracle
    function __initialize_ClearingHouse(
        address rageTradeFactoryAddress,
        IERC20 defaultCollateralToken,
        IOracle defaultCollateralTokenOracle,
        IInsuranceFund insuranceFund,
        IVBase vBase,
        IOracle nativeOracle
    ) external;

    function registerPool(address full, Pool calldata poolInfo) external;
}
