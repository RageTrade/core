//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';

contract VPoolWrapperMock is IVPoolWrapper {
    struct ValuesInside {
        uint256 sumA;
        uint256 sumBInside;
        uint256 sumFpInside;
        uint256 longsFeeGrowthInside;
        uint256 shortsFeeGrowthInside;
    }

    mapping(int24 => mapping(int24 => ValuesInside)) public getValuesInside;

    function setValuesInside(
        int24 tickLower,
        int24 tickUpper,
        uint256 sumA,
        uint256 sumBInside,
        uint256 sumFpInside,
        uint256 longsFeeGrowthInside,
        uint256 shortsFeeGrowthInside
    ) external {
        getValuesInside[tickLower][tickUpper].sumA = sumA;
        getValuesInside[tickLower][tickUpper].sumBInside = sumBInside;
        getValuesInside[tickLower][tickUpper].sumFpInside = sumFpInside;
        getValuesInside[tickLower][tickUpper].longsFeeGrowthInside = longsFeeGrowthInside;
        getValuesInside[tickLower][tickUpper].shortsFeeGrowthInside = shortsFeeGrowthInside;
    }
}
