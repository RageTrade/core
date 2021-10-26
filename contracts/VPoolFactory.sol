//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import './libraries/uniswapTwapSqrtPrice.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import './interfaces/IVPoolFactory.sol';
import './interfaces/IOracleContract.sol';
import './tokens/VToken.sol';
import './VPoolWrapper.sol';
import './Constants.sol';

abstract contract VPoolFactory is IVPoolFactory {
    struct Parameters {
        uint16 initialMargin;
        uint16 maintainanceMargin;
        uint32 twapDuration;
    }
    Parameters public override parameters;

    address public immutable owner;
    bool public isRestricted;

    mapping(bytes4 => address) public vTokenAddresses; // bytes4(vTokenAddress) => vTokenAddress
    mapping(address => bool) public realTokenInitilized;

    constructor() {
        isRestricted = true;
        owner = msg.sender;
    }

    event poolInitlized(address vPool, address vTokenAddress, address vPoolWrapper);

    function initializePool(
        string calldata vTokenName,
        string calldata vTokenSymbol,
        address realToken,
        address oracleAddress,
        uint16 initialMargin,
        uint16 maintainanceMargin,
        uint32 twapDuration
    ) external isAllowed {
        address vTokenAddress = _deployVToken(vTokenName, vTokenSymbol, realToken, oracleAddress);
        address vPool = IUniswapV3Factory(UNISWAP_FACTORY_ADDRESS).createPool(
            VBASE_ADDRESS,
            vTokenAddress,
            DEFAULT_FEE_TIER
        );
        IUniswapV3Pool(vPool).initialize(IOracleContract(oracleAddress).getSqrtPrice(twapDuration));
        address vPoolWrapper = _deployVPoolWrapper(vTokenAddress, initialMargin, maintainanceMargin, twapDuration);
        emit poolInitlized(vPool, vTokenAddress, vPoolWrapper);
    }

    function _deployVToken(
        string calldata vTokenName,
        string calldata vTokenSymbol,
        address realToken,
        address oracleAddress
    ) internal returns (address) {
        // Pool for this token must not be already created
        require(realTokenInitilized[realToken] == false, 'Duplicate Pool');

        uint160 salt = uint160(realToken);
        bytes memory bytecode = type(VToken).creationCode;
        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(vTokenName, vTokenSymbol, realToken, oracleAddress, address(this))
        );
        bytes32 byteCodeHash = keccak256(bytecode);
        bytes4 key;
        address vTokenAddress;
        while (true) {
            vTokenAddress = Create2.computeAddress(keccak256(abi.encode(salt)), byteCodeHash);
            key = bytes4(abi.encode(vTokenAddress));
            if (vTokenAddresses[key] == address(0)) {
                break;
            }
            salt++; // using a different salt
        }
        address deployedAddress = Create2.deploy(0, keccak256(abi.encode(salt)), bytecode);
        require(vTokenAddress == deployedAddress, 'Cal MisMatch'); // Can be disabled in mainnet deployment
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
        bytes32 salt = keccak256(abi.encode(vTokenAddress, VBASE_ADDRESS));
        bytes memory bytecode = type(VPoolWrapper).creationCode;
        parameters = Parameters({
            initialMargin: initialMargin,
            maintainanceMargin: maintainanceMargin,
            twapDuration: twapDuration
        });
        address deployedAddress = Create2.deploy(0, salt, bytecode);
        delete parameters;
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
