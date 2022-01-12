//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

import { Governable } from '../utils/Governable.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3Factory } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Factory.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IVBase } from '../interfaces/IVBase.sol';
import { VToken, IVToken } from '../tokens/VToken.sol';
import { IClearingHouse } from '../interfaces/IClearingHouse.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { ProxyAdmin } from '../proxy/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '../proxy/TransparentUpgradeableProxy.sol';

import { ClearingHouseDeployer } from './ClearingHouseDeployer.sol';
import { VBaseDeployer } from './VBaseDeployer.sol';
import { VTokenDeployer } from './VTokenDeployer.sol';
import { VPoolWrapperDeployer } from './VPoolWrapperDeployer.sol';
import { BaseOracle } from '../oracles/BaseOracle.sol';

import { console } from 'hardhat/console.sol';

contract RageTradeFactory is Ownable, ClearingHouseDeployer, VBaseDeployer, VTokenDeployer, VPoolWrapperDeployer {
    using VTokenLib for VTokenAddress;

    IVBase public immutable vBase;
    IClearingHouse public immutable clearingHouse;

    address public immutable UNISWAP_V3_FACTORY_ADDRESS;
    uint24 public immutable UNISWAP_V3_DEFAULT_FEE_TIER;
    bytes32 public immutable UNISWAP_V3_POOL_BYTE_CODE_HASH;

    event PoolInitlized(IUniswapV3Pool vPool, IVToken vToken, IVPoolWrapper vPoolWrapper);

    constructor(
        address clearingHouseLogicAddress,
        address _vPoolWrapperLogicAddress,
        address rBaseAddress,
        address insuranceFundAddress,
        address _UNISWAP_V3_FACTORY_ADDRESS,
        uint24 _UNISWAP_V3_DEFAULT_FEE_TIER,
        bytes32 _UNISWAP_V3_POOL_BYTE_CODE_HASH
    ) VPoolWrapperDeployer(_vPoolWrapperLogicAddress) {
        proxyAdmin = new ProxyAdmin();

        UNISWAP_V3_FACTORY_ADDRESS = _UNISWAP_V3_FACTORY_ADDRESS;
        UNISWAP_V3_DEFAULT_FEE_TIER = _UNISWAP_V3_DEFAULT_FEE_TIER;
        UNISWAP_V3_POOL_BYTE_CODE_HASH = _UNISWAP_V3_POOL_BYTE_CODE_HASH;

        vBase = _deployVBase(rBaseAddress);

        clearingHouse = _deployClearingHouse(
            ClearingHouseDeployer.DeployClearingHouseParams(
                clearingHouseLogicAddress,
                rBaseAddress,
                insuranceFundAddress,
                address(vBase),
                _UNISWAP_V3_FACTORY_ADDRESS,
                _UNISWAP_V3_DEFAULT_FEE_TIER,
                _UNISWAP_V3_POOL_BYTE_CODE_HASH
            )
        );
        Governable(address(clearingHouse)).transferGovernance(msg.sender);
        Governable(address(clearingHouse)).transferTeamMultisig(msg.sender);

        // TODO refactor the code such that registering vBase as a pool is not needed
        clearingHouse.registerPool(
            address(vBase),
            IClearingHouse.RageTradePool(
                IUniswapV3Pool(address(0)),
                IVPoolWrapper(address(0)),
                IClearingHouse.RageTradePoolSettings(0, 0, 60, false, new BaseOracle())
            )
        );

        // isRestricted = true;
        // vPoolWrapperDeployer = IVPoolWrapperDeployer(VPoolWrapperDeployerAddress);
        // constants = Constants(
        //     address(this),
        //     VPoolWrapperDeployerAddress,
        //     VBASE_ADDRESS,
        //     UNISWAP_FACTORY_ADDRESS,
        //     DEFAULT_FEE_TIER,
        //     POOL_BYTE_CODE_HASH,
        //     bytes32(0) // vPoolWrapperDeployer.byteCodeHash()
        // );
        // clearingHouse = IClearingHouse(ClearingHouseAddress);
    }

    struct InitializePoolParams {
        VTokenDeployer.DeployVTokenParams deployVTokenParams;
        IClearingHouse.RageTradePoolSettings rageTradePoolInitialSettings;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
    }

    function _createUniswapV3Pool(IVToken vToken) internal returns (IUniswapV3Pool) {
        return
            IUniswapV3Pool(
                IUniswapV3Factory(UNISWAP_V3_FACTORY_ADDRESS).createPool(
                    address(vBase),
                    address(vToken),
                    UNISWAP_V3_DEFAULT_FEE_TIER
                )
            );
    }

    function _isVTokenAddressGood(address addr) internal view virtual override returns (bool) {
        return
            super._isVTokenAddressGood(addr) &&
            (uint160(addr) < uint160(address(vBase))) &&
            clearingHouse.isVTokenAddressAvailable(uint32(uint160(addr)));
    }

    function initializePool(InitializePoolParams calldata initializePoolParams) external onlyOwner {
        // STEP 1: Deploy the virtual token ERC20, such that it will be token0
        IVToken vToken = _deployVToken(initializePoolParams.deployVTokenParams); // TODO fix this params

        // STEP 2: Deploy vPool (token0=vToken, token1=vBase) on actual uniswap
        IUniswapV3Pool vPool = _createUniswapV3Pool(vToken);

        // STEP 3: Initialize the price on the vPool
        vPool.initialize(
            IOracle(initializePoolParams.deployVTokenParams.oracleAddress).getTwapSqrtPriceX96(
                initializePoolParams.rageTradePoolInitialSettings.twapDuration
            )
        );

        // STEP 4: Deploy the wrapper contract for the vPool
        IVPoolWrapper vPoolWrapper = _deployVPoolWrapper(
            IVPoolWrapper.InitializeVPoolWrapperParams(
                clearingHouse,
                vToken,
                vBase,
                vPool,
                initializePoolParams.liquidityFeePips,
                initializePoolParams.protocolFeePips,
                UNISWAP_V3_DEFAULT_FEE_TIER
            )
        );

        // STEP 5: Authorize vPoolWrapper in vToken and vBase
        vBase.authorize(address(vPoolWrapper));
        vToken.setVPoolWrapper(address(vPoolWrapper));
        clearingHouse.registerPool(
            address(vToken),
            IClearingHouse.RageTradePool(vPool, vPoolWrapper, initializePoolParams.rageTradePoolInitialSettings)
        );

        emit PoolInitlized(vPool, vToken, vPoolWrapper);
    }

    // struct SetupVTokenParams {
    //     string vTokenName;
    //     string vTokenSymbol;
    //     address realTokenAddress; // TODO remove dependency on real token address, as it is not needed
    //     address oracleAddress;
    // }

    // function _deployVToken(
    //     SetupVTokenParams calldata setupVTokenParams,
    //     uint256 counter,
    //     address VBASE_ADDRESS
    // ) internal returns (address) {
    //     unchecked {
    //         // TODO change require to custom errors
    //         // Pool for this token must not be already created
    //         require(!clearingHouse.isRealTokenAlreadyInitilized(setupVTokenParams.realTokenAddress), 'Duplicate Pool');

    //         bytes memory bytecode = abi.encodePacked(
    //             type(VToken).creationCode,
    //             abi.encode(
    //                 setupVTokenParams.vTokenName,
    //                 setupVTokenParams.vTokenSymbol,
    //                 setupVTokenParams.realTokenAddress,
    //                 setupVTokenParams.oracleAddress,
    //                 address(this)
    //             )
    //         );
    //         bytes32 byteCodeHash = keccak256(bytecode);
    //         bytes32 salt;
    //         uint32 truncated;
    //         address vTokenAddressComputed;

    //         while (true) {
    //             salt = keccak256(abi.encode(counter, setupVTokenParams.realTokenAddress));
    //             vTokenAddressComputed = Create2.computeAddress(salt, byteCodeHash);
    //             truncated = uint32(uint160(vTokenAddressComputed));
    //             if (
    //                 truncated != 0 &&
    //                 uint160(vTokenAddressComputed) < uint160(VBASE_ADDRESS) &&
    //                 clearingHouse.isVTokenAddressAvailable(truncated)
    //             ) {
    //                 break;
    //             } else {
    //                 counter++; // using a different salt
    //             }
    //         }

    //         address vTokenAddressDeployed = Create2.deploy(0, salt, bytecode);
    //         assert(vTokenAddressComputed == vTokenAddressDeployed); // TODO disable in mainnet?

    //         clearingHouse.addVTokenAddress(truncated, vTokenAddressDeployed);
    //         clearingHouse.initRealToken(setupVTokenParams.realTokenAddress);

    //         return vTokenAddressDeployed;
    //     }
    // }

    // function _deployVPoolWrapper(
    //     address vTokenAddress,
    //     address vPoolAddress,
    //     address oracleAddress,
    //     uint24 liquidityFeePips,
    //     uint24 protocolFeePips,
    //     uint16 initialMarginRatio,
    //     uint16 maintainanceMarginRatio,
    //     uint32 twapDuration,
    //     bool whitelisted,
    //     address vBaseAddress
    // ) internal returns (address) {
    //     return
    //         address(
    //             new TransparentUpgradeableProxy(
    //                 vPoolWrapperLogicAddress,
    //                 address(proxyAdmin),
    //                 abi.encodeWithSelector(
    //                     IVPoolWrapper.initialize.selector,
    //                     vTokenAddress,
    //                     vPoolAddress,
    //                     oracleAddress,
    //                     liquidityFeePips,
    //                     protocolFeePips,
    //                     initialMarginRatio,
    //                     maintainanceMarginRatio,
    //                     twapDuration,
    //                     whitelisted,
    //                     vBaseAddress
    //                 )
    //             )
    //         );
    // }

    // function allowCustomPools(bool _status) external onlyOwner {
    //     isRestricted = _status;
    // }

    // modifier isAllowed() {
    //     require((msg.sender == owner || isRestricted == false), 'Not Allowed');
    //     _;
    // }
    // modifier onlyOwner() {
    //     require(msg.sender == owner, 'Not Owner');
    //     _;
    // }
}
