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
import { IClearingHouse } from './interfaces/IClearingHouse.sol';
import { IVPoolWrapper } from './interfaces/IVPoolWrapper.sol';
import { VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';

import { console } from 'hardhat/console.sol';

contract VPoolFactory {
    using VTokenLib for VTokenAddress;

    Constants public constants;

    address public immutable owner;
    bool public isRestricted;

    IClearingHouse public immutable clearingHouse;
    IVPoolWrapperDeployer public immutable vPoolWrapperDeployer;

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
        vPoolWrapperDeployer = IVPoolWrapperDeployer(VPoolWrapperDeployerAddress);
        constants = Constants(
            address(this),
            VPoolWrapperDeployerAddress,
            VBASE_ADDRESS,
            UNISWAP_FACTORY_ADDRESS,
            DEFAULT_FEE_TIER,
            POOL_BYTE_CODE_HASH,
            vPoolWrapperDeployer.byteCodeHash()
        );
        clearingHouse = IClearingHouse(ClearingHouseAddress);
        clearingHouse.setConstants(constants);
        clearingHouse.addVTokenAddress(VTokenAddress.wrap(VBASE_ADDRESS).truncate(), VBASE_ADDRESS);
    }

    event PoolInitlized(address vPoolAddress, address vTokenAddress, address vPoolWrapperAddress);

    struct SetupVTokenParams {
        string vTokenName;
        string vTokenSymbol;
        address realTokenAddress; // TODO remove dependency on real token address, as it is not needed
        address oracleAddress;
    }

    struct InitializePoolParams {
        SetupVTokenParams setupVTokenParams;
        uint24 extendedLpFee;
        uint24 protocolFee;
        uint16 initialMarginRatio;
        uint16 maintainanceMarginRatio;
        uint32 twapDuration;
        bool whitelisted;
    }

    function initializePool(InitializePoolParams calldata ipParams, uint256 salt) external isAllowed {
        address vTokenAddress = _deployVToken(ipParams.setupVTokenParams, salt, constants.VBASE_ADDRESS);
        address vPoolAddress = IUniswapV3Factory(constants.UNISWAP_FACTORY_ADDRESS).createPool(
            constants.VBASE_ADDRESS,
            vTokenAddress,
            constants.DEFAULT_FEE_TIER
        );
        IUniswapV3Pool(vPoolAddress).initialize(
            IOracle(ipParams.setupVTokenParams.oracleAddress).getTwapSqrtPriceX96(ipParams.twapDuration)
        );
        address vPoolWrapper = vPoolWrapperDeployer.deployVPoolWrapper(
            vTokenAddress,
            vPoolAddress,
            ipParams.setupVTokenParams.oracleAddress,
            ipParams.extendedLpFee,
            ipParams.protocolFee,
            ipParams.initialMarginRatio,
            ipParams.maintainanceMarginRatio,
            ipParams.twapDuration,
            ipParams.whitelisted,
            constants
        );
        IVPoolWrapper(vPoolWrapper).setOracle(ipParams.setupVTokenParams.oracleAddress);
        IVBase(constants.VBASE_ADDRESS).authorize(vPoolWrapper);
        IVToken(vTokenAddress).setOwner(vPoolWrapper); // TODO remove this
        emit PoolInitlized(vPoolAddress, vTokenAddress, vPoolWrapper);
    }

    function _deployVToken(
        SetupVTokenParams calldata setupVTokenParams,
        uint256 counter,
        address VBASE_ADDRESS
    ) internal returns (address) {
        unchecked {
            // TODO change require to custom errors
            // Pool for this token must not be already created
            require(!clearingHouse.isRealTokenAlreadyInitilized(setupVTokenParams.realTokenAddress), 'Duplicate Pool');

            bytes memory bytecode = abi.encodePacked(
                type(VToken).creationCode,
                abi.encode(
                    setupVTokenParams.vTokenName,
                    setupVTokenParams.vTokenSymbol,
                    setupVTokenParams.realTokenAddress,
                    setupVTokenParams.oracleAddress,
                    address(this)
                )
            );
            bytes32 byteCodeHash = keccak256(bytecode);
            bytes32 salt;
            uint32 truncated;
            address vTokenAddressComputed;

            while (true) {
                salt = keccak256(abi.encode(counter, setupVTokenParams.realTokenAddress));
                vTokenAddressComputed = Create2.computeAddress(salt, byteCodeHash);
                truncated = uint32(uint160(vTokenAddressComputed));
                if (
                    truncated != 0 &&
                    uint160(vTokenAddressComputed) < uint160(VBASE_ADDRESS) &&
                    clearingHouse.isVTokenAddressAvailable(truncated)
                ) {
                    break;
                } else {
                    counter++; // using a different salt
                }
            }

            address vTokenAddressDeployed = Create2.deploy(0, salt, bytecode);
            assert(vTokenAddressComputed == vTokenAddressDeployed); // TODO disable in mainnet?

            clearingHouse.addVTokenAddress(truncated, vTokenAddressDeployed);
            clearingHouse.initRealToken(setupVTokenParams.realTokenAddress);

            return vTokenAddressDeployed;
        }
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
