//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol';
import { IUniswapV3Factory } from '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Factory.sol';

import { ClearingHouseDeployer } from './clearinghouse/ClearingHouseDeployer.sol';
import { InsuranceFundDeployer } from './insurancefund/InsuranceFundDeployer.sol';
import { VBaseDeployer } from './tokens/VBaseDeployer.sol';
import { VTokenDeployer } from './tokens/VTokenDeployer.sol';
import { VToken } from './tokens/VToken.sol';
import { VBaseDeployer, IVBase } from './tokens/VBaseDeployer.sol';
import { VTokenDeployer, IVToken } from './tokens/VTokenDeployer.sol';
import { VPoolWrapperDeployer, IVPoolWrapper } from './wrapper/VPoolWrapperDeployer.sol';

import { IERC20Metadata } from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import { IOracle } from '../interfaces/IOracle.sol';
import { IVBase } from '../interfaces/IVBase.sol';
import { IVPoolWrapper } from '../interfaces/IVPoolWrapper.sol';
import { IVToken } from '../interfaces/IVToken.sol';

import { AddressHelper } from '../libraries/AddressHelper.sol';
import { PriceMath } from '../libraries/PriceMath.sol';

import { BaseOracle } from '../oracles/BaseOracle.sol';
import { Governable } from '../utils/Governable.sol';

import { UNISWAP_V3_FACTORY_ADDRESS, UNISWAP_V3_DEFAULT_FEE_TIER } from '../utils/constants.sol';

import { console } from 'hardhat/console.sol';

contract RageTradeFactory is
    Governable,
    ClearingHouseDeployer,
    InsuranceFundDeployer,
    VBaseDeployer,
    VPoolWrapperDeployer,
    VTokenDeployer
{
    using AddressHelper for address;
    using PriceMath for uint256;

    IVBase public immutable vBase;
    IClearingHouse public immutable clearingHouse;
    // IInsuranceFund public insuranceFund; // stored in ClearingHouse, replacable from there

    event PoolInitialized(IUniswapV3Pool vPool, IVToken vToken, IVPoolWrapper vPoolWrapper);

    /// @notice Sets up the protocol by deploying necessary core contracts
    /// @dev Need to deploy logic contracts for ClearingHouse, VPoolWrapper, InsuranceFund prior to this
    constructor(
        address clearingHouseLogicAddress,
        address _vPoolWrapperLogicAddress,
        address insuranceFundLogicAddress,
        IERC20Metadata cBase,
        IOracle nativeOracle
    ) VPoolWrapperDeployer(_vPoolWrapperLogicAddress) {
        proxyAdmin = _deployProxyAdmin();
        proxyAdmin.transferOwnership(msg.sender);

        // deploys VBase contract at an address which has most significant nibble as "f"
        vBase = _deployVBase(cBase.decimals());

        // deploys InsuranceFund proxy
        IInsuranceFund insuranceFund = _deployProxyForInsuranceFund(insuranceFundLogicAddress);

        BaseOracle cBaseOracle = new BaseOracle();

        // deploys a proxy for ClearingHouse, and initialize it as well
        clearingHouse = _deployProxyForClearingHouseAndInitialize(
            ClearingHouseDeployer.DeployClearingHouseParams(
                clearingHouseLogicAddress,
                cBase,
                cBaseOracle,
                insuranceFund,
                vBase,
                nativeOracle
            )
        );
        clearingHouse.transferGovernance(msg.sender);
        clearingHouse.transferTeamMultisig(msg.sender);

        _initializeInsuranceFund(insuranceFund, cBase, clearingHouse);
    }

    struct InitializePoolParams {
        VTokenDeployer.DeployVTokenParams deployVTokenParams;
        IClearingHouseStructures.PoolSettings poolInitialSettings;
        uint24 liquidityFeePips;
        uint24 protocolFeePips;
        uint16 slotsToInitialize;
    }

    /// @notice Sets up a new Rage Trade Pool by deploying necessary contracts
    /// @dev An already deployed oracle contract address (implementing IOracle) is needed prior to using this
    /// @param initializePoolParams parameters for initializing the pool
    function initializePool(InitializePoolParams calldata initializePoolParams) external onlyGovernance {
        // TODO change wrapper deployment to use CREATE2 so that we can pass wrapper address
        // as an argument to vtoken constructer and make wrapper variable as immutable.
        // this will save sload on all vtoken mints (swaps liqudity adds).
        // STEP 1: Deploy the virtual token ERC20, such that it will be token0
        IVToken vToken = _deployVToken(initializePoolParams.deployVTokenParams);

        // STEP 2: Deploy vPool (token0=vToken, token1=vBase) on actual uniswap
        IUniswapV3Pool vPool = _createUniswapV3Pool(vToken);

        // STEP 3: Initialize the price on the vPool
        vPool.initialize(
            initializePoolParams
                .poolInitialSettings
                .oracle
                .getTwapPriceX128(initializePoolParams.poolInitialSettings.twapDuration)
                .toSqrtPriceX96()
        );

        vPool.increaseObservationCardinalityNext(initializePoolParams.slotsToInitialize);

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
            IClearingHouseStructures.Pool(vToken, vPool, vPoolWrapper, initializePoolParams.poolInitialSettings)
        );

        emit PoolInitialized(vPool, vToken, vPoolWrapper);
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

    function _isIVTokenAddressGood(address addr) internal view virtual override returns (bool) {
        uint32 poolId = addr.truncate();
        return
            // Zero element is considered empty in Uint32L8Array.sol
            poolId != 0 &&
            // vToken should be token0 and vBase should be token1 in UniswapV3Pool
            (uint160(addr) < uint160(address(vBase))) &&
            // there should not be a collision in poolIds
            clearingHouse.isPoolIdAvailable(poolId);
    }
}
