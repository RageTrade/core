//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolFactory.sol';
import { VBASE_ADDRESS, VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';
import '@uniswap/v3-periphery/contracts/libraries/PositionKey.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/IVBase.sol';
import './interfaces/IVToken.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback {
    using VTokenLib for VTokenAddress;
    uint16 public immutable initialMarginRatio;
    uint16 public immutable maintainanceMarginRatio;
    uint32 public immutable timeHorizon;
    VTokenAddress public immutable vToken;

    constructor() {
        address vTokenAddress;
        (vTokenAddress, initialMarginRatio, maintainanceMarginRatio, timeHorizon) = IVPoolFactory(msg.sender)
            .parameters();
        vToken = VTokenAddress.wrap(vTokenAddress);
    }

    function getValuesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int256 sumA,
            int256 sumBInside,
            int256 sumFpInside,
            uint256 longsFeeInside,
            uint256 shortsFeeInside
        )
    {}

    function liquidityChange(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidity
    ) external returns (int256 basePrincipal, int256 vTokenPrincipal) {
        int256 amount0;
        int256 amount1;
        if (liquidity > 0) {
            uint256 _amount0;
            uint256 _amount1;
            (_amount0, _amount1) = vToken.vPool().mint({
                recipient: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity),
                data: '0x'
            });
            amount0 = int256(_amount0);
            amount1 = int256(_amount1);
        } else {
            uint256 _amount0;
            uint256 _amount1;
            (_amount0, _amount1) = vToken.vPool().burn({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity)
            });
            amount0 = int256(_amount0) * -1;
            amount1 = int256(_amount1) * -1;
        }
        (basePrincipal, vTokenPrincipal) = vToken.flip(amount0, amount1);

        // the above uniswapPool.mint or uniswapPool.burn updates fee growth for the position state

        // bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        // (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = vToken.vPool().positions(
        //     positionKey
        // );
        // (feeGrowthInsideVBaseLastX128, feeGrowthInsideVTokenLastX128) = vToken.flip(
        //     feeGrowthInside0LastX128,
        //     feeGrowthInside1LastX128
        // );

        if (liquidity < 0) collectAndBurn(tickLower, tickUpper); // D
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(vToken.vPool()));
        (int256 vBaseAmount, int256 vTokenAmount) = vToken.flip(int256(amount0), int256(amount1));
        if (vBaseAmount > 0) IVBase(VBASE_ADDRESS).mint(msg.sender, uint256(vBaseAmount));
        if (vTokenAmount > 0) IVToken(VTokenAddress.unwrap(vToken)).mint(msg.sender, uint256(vTokenAmount));
    }

    function collectAndBurn(int24 tickLower, int24 tickUpper) internal {
        (uint256 amount0, uint256 amount1) = vToken.vPool().collect({
            recipient: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Requested: type(uint128).max,
            amount1Requested: type(uint128).max
        });
        (int256 basePrincipalPlusLongFees, int256 vTokenPrincipalPlusShortFees) = vToken.flip(
            int256(amount0),
            int256(amount1)
        );

        // burn ERC20 tokens sent by uniswap and fwd accounting to perp state
        IVBase(VBASE_ADDRESS).burn(msg.sender, uint256(basePrincipalPlusLongFees));
        IVToken(VTokenAddress.unwrap(vToken)).burn(msg.sender, uint256(vTokenPrincipalPlusShortFees));
    }

    function getExtrapolatedSumA() external pure returns (int256) {
        return 0;
    }
}
