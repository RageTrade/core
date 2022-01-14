//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IClearingHouse } from '../interfaces/IClearingHouse.sol';

interface IInsuranceFund {
    function __InsuranceFund_init(
        IERC20 rBase,
        IClearingHouse clearingHouse,
        string calldata name,
        string calldata symbol
    ) external;

    function claim(uint256 amount) external;
}
