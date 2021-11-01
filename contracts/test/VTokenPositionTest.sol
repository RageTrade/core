//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import { VTokenType, VTokenPosition } from '../libraries/VTokenPosition.sol';

contract VTokenPositionTest {
    using VTokenPosition for VTokenPosition.Position;
    uint256 num;
    mapping(uint256 => VTokenPosition.Position) internal dummys;

    function init(
        address _vTokenAddress,
        int256 _balance,
        int256 _netTraderPosition,
        int256 _sumAChkpt
    ) external {
        VTokenPosition.Position storage dummy = dummys[num++];
        dummy.vToken = VTokenType.wrap(_vTokenAddress);
        dummy.balance = _balance;
        dummy.netTraderPosition = _netTraderPosition;
        dummy.sumAChkpt = _sumAChkpt;
    }

    function getTokenPositionValue(uint256 price) external view returns (int256 value) {
        return dummys[0].getTokenPositionValue(price);
    }

    function riskSide() external view returns (uint8) {
        return uint8(dummys[0].riskSide());
    }

    function isInitilized() external view returns (bool) {
        return (dummys[0].isInitialized());
    }
}
