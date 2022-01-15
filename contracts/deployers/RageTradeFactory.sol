//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Create2 } from '@openzeppelin/contracts/utils/Create2.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3Factory } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Factory.sol';

import { ClearingHouseDeployer, IClearingHouse } from './ClearingHouseDeployer.sol';
import { InsuranceFundDeployer, IInsuranceFund } from './InsuranceFundDeployer.sol';
import { VBaseDeployer, IVBase } from './VBaseDeployer.sol';
import { VTokenDeployer, IVToken } from './VTokenDeployer.sol';
import { VPoolWrapperDeployer, IVPoolWrapper } from './VPoolWrapperDeployer.sol';

import { IOracle } from '../interfaces/IOracle.sol';
import { VTokenAddress, VTokenLib } from '../libraries/VTokenLib.sol';
import { BaseOracle } from '../oracles/BaseOracle.sol';
import { VToken } from '../tokens/VToken.sol';
import { Governable } from '../utils/Governable.sol';

import { console } from 'hardhat/console.sol';

contract RageTradeFactory is
    Governable,
    ClearingHouseDeployer,
    InsuranceFundDeployer,
    VBaseDeployer,
    VPoolWrapperDeployer,
    VTokenDeployer
{
    using VTokenLib for VTokenAddress;

    address public immutable UNISWAP_V3_FACTORY_ADDRESS;
    uint24 public immutable UNISWAP_V3_DEFAULT_FEE_TIER;
    bytes32 public immutable UNISWAP_V3_POOL_BYTE_CODE_HASH;

    IVBase public immutable vBase;
    IClearingHouse public immutable clearingHouse;
    // IInsuranceFund public insuranceFund; // stored in ClearingHouse, replacable from there

    event PoolInitlized(IUniswapV3Pool vPool, IVToken vToken, IVPoolWrapper vPoolWrapper);

    /// @notice Sets up the protocol by deploying necessary core contracts
    /// @dev Need to deploy logic contracts for ClearingHouse, VPoolWrapper, InsuranceFund prior to this
    constructor(
        address clearingHouseLogicAddress,
        address _vPoolWrapperLogicAddress,
        address rBaseAddress,
        address insuranceFundLogicAddress,
        address nativeOracle,
        address _UNISWAP_V3_FACTORY_ADDRESS,
        uint24 _UNISWAP_V3_DEFAULT_FEE_TIER,
        bytes32 _UNISWAP_V3_POOL_BYTE_CODE_HASH
    ) VPoolWrapperDeployer(_vPoolWrapperLogicAddress) {
        proxyAdmin = _deployProxyAdmin();
        proxyAdmin.transferOwnership(msg.sender);

        UNISWAP_V3_FACTORY_ADDRESS = _UNISWAP_V3_FACTORY_ADDRESS;
        UNISWAP_V3_DEFAULT_FEE_TIER = _UNISWAP_V3_DEFAULT_FEE_TIER;
        UNISWAP_V3_POOL_BYTE_CODE_HASH = _UNISWAP_V3_POOL_BYTE_CODE_HASH;

        // deploys VBase contract at an address which has most significant nibble as "f"
        vBase = _deployVBase(rBaseAddress);

        // deploys InsuranceFund proxy
        IInsuranceFund insuranceFund = _deployProxyForInsuranceFund(insuranceFundLogicAddress);

        // deploys a proxy for ClearingHouse, and initialize it as well
        clearingHouse = _deployProxyForClearingHouseAndInitialize(
            ClearingHouseDeployer.DeployClearingHouseParams(
                clearingHouseLogicAddress,
                rBaseAddress,
                address(insuranceFund),
                address(vBase),
                nativeOracle
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

        _initializeInsuranceFund(insuranceFund, vBase, clearingHouse);
    }

    struct InitializePoolParams {
        VTokenDeployer.DeployVTokenParams deployVTokenParams;
        IClearingHouse.RageTradePoolSettings rageTradePoolInitialSettings;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
    }

    /// @notice Sets up a new Rage Trade Pool by deploying necessary contracts
    /// @dev An already deployed oracle contract address (implementing IOracle) is needed prior to using this
    /// @param initializePoolParams parameters for initializing the pool
    function initializePool(InitializePoolParams calldata initializePoolParams) external onlyGovernance {
        // STEP 1: Deploy the virtual token ERC20, such that it will be token0
        IVToken vToken = _deployVToken(initializePoolParams.deployVTokenParams);

        // STEP 2: Deploy vPool (token0=vToken, token1=vBase) on actual uniswap
        IUniswapV3Pool vPool = _createUniswapV3Pool(vToken);

        // STEP 3: Initialize the price on the vPool
        vPool.initialize(
            IOracle(initializePoolParams.deployVTokenParams.oracleAddress).getTwapSqrtPriceX96(
                initializePoolParams.rageTradePoolInitialSettings.twapDuration
            )
        );

        // STEP 4: Deploys a proxy for the wrapper contract for the vPool, and initialize it as well
        IVPoolWrapper vPoolWrapper = _deployProxyForVPoolWrapperAndInitialize(
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

        // STEP 5: Authorize vPoolWrapper in vToken and vBase, for minting/burning whenever needed
        vBase.authorize(address(vPoolWrapper));
        vToken.setVPoolWrapper(address(vPoolWrapper));
        clearingHouse.registerPool(
            address(vToken),
            IClearingHouse.RageTradePool(vPool, vPoolWrapper, initializePoolParams.rageTradePoolInitialSettings)
        );

        emit PoolInitlized(vPool, vToken, vPoolWrapper);
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
}
