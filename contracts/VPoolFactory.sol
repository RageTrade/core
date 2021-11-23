//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3Factory } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import { Constants } from './utils/Constants.sol';
import { IOracle } from './interfaces/IOracle.sol';
import { IVBase } from './interfaces/IVBase.sol';
import { VToken, IVToken } from './tokens/VToken.sol';
import { IVPoolWrapperDeployer } from './interfaces/IVPoolWrapperDeployer.sol';
import { IClearingHouseState } from './interfaces/IClearingHouseState.sol';

contract VPoolFactory {
    Constants public constants;

    address public immutable owner;
    bool public isRestricted;

    IClearingHouseState public ClearingHouse;
    IVPoolWrapperDeployer public VPoolWrapperDeployer;

    constructor(
        address VBASE_ADDRESS,
        address ClearingHouseAddress,
        address VPoolWrapperDeployerAddress,
        address UNISWAP_FACTORY_ADDRESS,
        uint24 DEFAULT_FEE_TIER,
        bytes32 POOL_BYTE_CODE_HASH
    ) {
        isRestricted = true;
        owner = msg.sender;
        VPoolWrapperDeployer = IVPoolWrapperDeployer(VPoolWrapperDeployerAddress);
        constants = Constants(
            address(this),
            VPoolWrapperDeployerAddress,
            VBASE_ADDRESS,
            UNISWAP_FACTORY_ADDRESS,
            DEFAULT_FEE_TIER,
            POOL_BYTE_CODE_HASH,
            VPoolWrapperDeployer.byteCodeHash()
        );
        ClearingHouse = IClearingHouseState(ClearingHouseAddress);
        ClearingHouse.setConstants(constants);
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
        address vPool = IUniswapV3Factory(constants.UNISWAP_FACTORY_ADDRESS).createPool(
            constants.VBASE_ADDRESS,
            vTokenAddress,
            constants.DEFAULT_FEE_TIER
        );
        IUniswapV3Pool(vPool).initialize(IOracle(oracleAddress).getTwapSqrtPriceX96(twapDuration));
        address vPoolWrapper = VPoolWrapperDeployer.deployVPoolWrapper(
            vTokenAddress,
            vPool,
            initialMargin,
            maintainanceMargin,
            twapDuration,
            constants
        );
        IVBase(constants.VBASE_ADDRESS).authorize(vPoolWrapper);
        IVToken(vTokenAddress).setOwner(vPoolWrapper); // TODO remove this
        emit poolInitlized(vPool, vTokenAddress, vPoolWrapper);
    }

    function _deployVToken(
        string calldata vTokenName,
        string calldata vTokenSymbol,
        address realToken,
        address oracleAddress
    ) internal returns (address) {
        // Pool for this token must not be already created
        require(ClearingHouse.isRealTokenAlreadyInitilized(realToken) == false, 'Duplicate Pool');

        uint160 salt = uint160(realToken);
        bytes memory bytecode = type(VToken).creationCode;
        // TODO compute vPoolWrapper address here and pass it to vToken contract as immutable
        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(vTokenName, vTokenSymbol, realToken, oracleAddress, address(this))
        );
        bytes32 byteCodeHash = keccak256(bytecode);
        uint32 key;
        address vTokenAddress;
        while (true) {
            vTokenAddress = Create2.computeAddress(keccak256(abi.encode(salt)), byteCodeHash);
            key = uint32(uint160(vTokenAddress));
            if (ClearingHouse.isKeyAvailable(key)) {
                break;
            }
            salt++; // using a different salt
        }
        address deployedAddress = Create2.deploy(0, keccak256(abi.encode(salt)), bytecode);
        require(vTokenAddress == deployedAddress, 'Cal MisMatch'); // Can be disabled in mainnet deployment
        ClearingHouse.addKey(key, deployedAddress);
        ClearingHouse.initRealToken(realToken);
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
