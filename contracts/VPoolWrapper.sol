//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import './libraries/uniswap/SafeCast.sol';
import './interfaces/IVPoolWrapper.sol';
import './interfaces/IVPoolFactory.sol';
import { VBASE_ADDRESS, VTokenAddress, VTokenLib, IUniswapV3Pool } from './libraries/VTokenLib.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/IVBase.sol';
import './interfaces/IVToken.sol';

contract VPoolWrapper is IVPoolWrapper, IUniswapV3MintCallback {
    using SafeCast for uint256;
    using VTokenLib for VTokenAddress;
    uint16 public immutable initialMarginRatio;
    uint16 public immutable maintainanceMarginRatio;
    uint32 public immutable timeHorizon;
    VTokenAddress public immutable vToken;
    IUniswapV3Pool public immutable vPool;

    constructor() {
        address vTokenAddress;
        (vTokenAddress, initialMarginRatio, maintainanceMarginRatio, timeHorizon) = IVPoolFactory(msg.sender)
            .parameters();
        vToken = VTokenAddress.wrap(vTokenAddress);
        vPool = vToken.vPool();
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
            (uint256 _amount0, uint256 _amount1) = vPool.mint({
                recipient: address(this),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity),
                data: '0x'
            });
            amount0 = _amount0.toInt256();
            amount1 = _amount1.toInt256();
        } else {
            (uint256 _amount0, uint256 _amount1) = vPool.burn({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount: uint128(liquidity * -1)
            });
            amount0 = _amount0.toInt256() * -1;
            amount1 = _amount1.toInt256() * -1;
            // review : do we want final amount here with fees included or just the am for liq ?
            // As per spec its am for liq only
            collect(tickLower, tickUpper);
        }
        (basePrincipal, vTokenPrincipal) = vToken.flip(amount0, amount1);
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == address(vPool));
        (int256 vBaseAmount, int256 vTokenAmount) = vToken.flip(amount0.toInt256(), amount1.toInt256());
        if (vBaseAmount > 0) IVBase(VBASE_ADDRESS).mint(msg.sender, uint256(vBaseAmount));
        if (vTokenAmount > 0) IVToken(VTokenAddress.unwrap(vToken)).mint(msg.sender, uint256(vTokenAmount));
    }

    function collect(int24 tickLower, int24 tickUpper) internal {
        (uint256 amount0, uint256 amount1) = vPool.collect({
            recipient: address(this),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Requested: type(uint128).max,
            amount1Requested: type(uint128).max
        });
        (int256 basePrincipalPlusLongFees, int256 vTokenPrincipalPlusShortFees) = vToken.flip(
            amount0.toInt256(),
            amount1.toInt256()
        );

        // burn ERC20 tokens sent by uniswap and fwd accounting to perp state
        IVBase(VBASE_ADDRESS).burn(address(this), uint256(basePrincipalPlusLongFees));
        IVToken(VTokenAddress.unwrap(vToken)).burn(address(this), uint256(vTokenPrincipalPlusShortFees));
    }

    function getExtrapolatedSumA() external pure returns (int256) {
        return 0;
    }

    function swapTokenNotional(int256 vBaseAmount) external returns (int256) {
        //TODO
        return 0;
    }

    function swapTokenAmount(int256 vTokenAmount) external returns (int256) {
        //TODO
        return 0;
    }
}
