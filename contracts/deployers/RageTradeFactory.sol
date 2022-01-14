//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';

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

contract RageTradeFactory is Governable, ClearingHouseDeployer, VBaseDeployer, VTokenDeployer, VPoolWrapperDeployer {
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
        proxyAdmin = _deployProxyAdmin();
        proxyAdmin.transferOwnership(msg.sender);

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

    function initializePool(InitializePoolParams calldata initializePoolParams) external onlyGovernance {
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
}
