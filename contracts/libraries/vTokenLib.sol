//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;
import '../Constants.sol';
import '../interfaces/IvToken.sol';
import '../interfaces/IvPoolWrapper.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import '../libraries/uniswapTwapSqrtPrice.sol';

type VToken is address;

library VTokenLib {
    
    function isToken0(address vToken) internal pure returns (bool) {
        return uint160(vToken) < uint160(VBASE_ADDRESS);
    }

    function isToken1(address vToken) internal pure returns (bool){
        return !isToken0(vToken);
    }

    function vPool(VToken vToken) internal pure returns (address){
        address token0;
        address token1;
        address vTokenAddress = VToken.unwrap(vToken);

        if(isToken0(vTokenAddress))
        {
            token0 = vTokenAddress;
            token1 = VBASE_ADDRESS;
        }
        else
        {
            token0 = VBASE_ADDRESS;
            token1 = vTokenAddress;
        }
        return Create2.computeAddress(keccak256(abi.encode(token0, token1, DEFAULT_FEE_TIER)) ,POOL_BYTE_CODE_HASH, DEPLOYER);
    }
    
    function vPoolWrapper(VToken vToken) internal pure returns (address) {
        return Create2.computeAddress(keccak256(abi.encodePacked(VToken.unwrap(vToken), VBASE_ADDRESS)),WRAPPER_BYTE_CODE_HASH, DEPLOYER);
    }
    
    function realToken(VToken vToken) internal view returns (address) {
        return IvToken(VToken.unwrap(vToken)).realToken(); // TODO implement
    }

    function realPool(VToken vToken) internal view returns (address) {
        address token0;
        address token1;
        address realTokenAddress = realToken(vToken);

        if(isToken0(realTokenAddress))
        {
            token0 = realTokenAddress;
            token1 = REAL_BASE_ADDRESS;
        }
        else
        {
            token0 = REAL_BASE_ADDRESS;
            token1 = realTokenAddress;
        }
        // Dependancy : Real Pool has to be of DEFAULT_FEE_TIER
        return Create2.computeAddress(keccak256(abi.encode(token0, token1, DEFAULT_FEE_TIER)) ,POOL_BYTE_CODE_HASH, DEPLOYER);
    }

    function getVirtualTwapSqrtPrice(VToken vToken) internal view returns (uint160) {
        IvPoolWrapper poolWrapper = IvPoolWrapper(vPoolWrapper(vToken));
        return getVirtualTwapSqrtPrice(vToken, poolWrapper.timeHorizon());
    }

    function getRealTwapSqrtPrice(VToken vToken) internal view returns (uint160) {
        IvPoolWrapper poolWrapper = IvPoolWrapper(vPoolWrapper(vToken));
        return getRealTwapSqrtPrice(vToken, poolWrapper.timeHorizon());
    }

    function getVirtualTwapSqrtPrice(VToken vToken, uint32 twapDuration) internal view returns (uint160) {
        return UniswapTwapSqrtPrice.get(vPool(vToken), twapDuration);
    }

    function getRealTwapSqrtPrice(VToken vToken, uint32 twapDuration) internal view returns (uint160) {
        return UniswapTwapSqrtPrice.get(realPool(vToken), twapDuration);
    }

    function getMarginRatio(VToken vToken, bool isInitialMargin) internal view returns (uint16){
        IvPoolWrapper poolWrapper = IvPoolWrapper(vPoolWrapper(vToken));
        if(isInitialMargin){
            return poolWrapper.initialMarginRatio();
        } else {
            return poolWrapper.maintainanceMarginRatio();
        }
    }
}
