//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './libraries/uniswapTwapSqrtPrice.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import './vToken.sol';
import './VPoolWrapper.sol';
import './Constants.sol';

abstract contract VPoolFactory {
    address public immutable owner;
    bool public isRestricted;

    mapping(bytes4 => address) public vTokenAddresses; // bytes4(vTokenAddress) => vTokenAddress
    mapping(address => bool) public realTokenInitilized;

    constructor() {
        isRestricted = true;
        owner = msg.sender;
    }

    // Dependancy : Real Pool has to be of DEFAULT_FEE_TIER
    function initializePool(
        address realPool,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration
    ) external isAllowed returns (address vTokenAddress, address vPoolWrapper) {
        address realToken = _getTokenOtherThanRealBase(realPool);
        vTokenAddress = _deployVToken(realToken);

        address vPool = IUniswapV3Factory(UNISWAP_FACTORY_ADDRESS).createPool(
            VBASE_ADDRESS,
            vTokenAddress,
            DEFAULT_FEE_TIER
        );
        IUniswapV3Pool(vPool).initialize(UniswapTwapSqrtPrice.get(realPool, twapDuration));
        vPoolWrapper = _deployVPoolWrapper(vTokenAddress, initialMargin, maintainanceMargin, twapDuration);
    }

    function _getTokenOtherThanRealBase(address realPoolAddress) internal view returns (address realToken) {
        IUniswapV3Pool realPool = IUniswapV3Pool(realPoolAddress);
        require(realPool.fee() == DEFAULT_FEE_TIER, 'Fee Tier MisMatch');
        address token0 = realPool.token0();
        address token1 = realPool.token1();
        if (token0 == REAL_BASE_ADDRESS) realToken = token1;
        else if (token1 == REAL_BASE_ADDRESS) realToken = token0;
        else revert('Real Base Not Found');
    }

    function _deployVToken(address realToken) internal returns (address) {
        // Pool for this token must not be already created
        require(realTokenInitilized[realToken] == false, 'Duplicate Pool');

        uint256 salt = uint160(realToken);
        bytes memory bytecode = type(vToken).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(realToken, address(this)));
        bytes32 byteCodeHash = keccak256(bytecode);
        bytes4 key;

        while (true) {
            address vTokenAddress = Create2.computeAddress(keccak256(abi.encodePacked(salt)), byteCodeHash);
            key = bytes4(abi.encodePacked(vTokenAddress));
            if (vTokenAddresses[key] == address(0)) {
                break;
            }
            salt++; // using a different salt
        }
        address deployedAddress = Create2.deploy(0, keccak256(abi.encodePacked(salt)), bytecode);
        // test here if it matches vTokenAddress
        vTokenAddresses[key] = deployedAddress;
        realTokenInitilized[realToken] == true;
        return deployedAddress;
    }

    function _deployVPoolWrapper(
        address vTokenAddress,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration
    ) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(vTokenAddress, VBASE_ADDRESS));
        bytes memory bytecode = type(VPoolWrapper).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(twapDuration, initialMargin, maintainanceMargin));
        address deployedAddress = Create2.deploy(0, keccak256(abi.encodePacked(salt)), bytecode);
        return deployedAddress;
    }

    function allowCustomPools(bool _status) external onlyOwner {
        isRestricted = _status;
    }

    modifier isAllowed() {
        require((msg.sender == owner || isRestricted == false), 'Not Allowed');
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, 'Not Owner');
        _;
    }
}
