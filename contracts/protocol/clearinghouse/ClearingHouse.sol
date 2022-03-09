//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from '../../libraries/Account.sol';
import { AddressHelper } from '../../libraries/AddressHelper.sol';
import { Calldata } from '../../libraries/Calldata.sol';
import { Protocol } from '../../libraries/Protocol.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { VTokenPositionSet } from '../../libraries/VTokenPositionSet.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { IClearingHouseActions } from '../../interfaces/clearinghouse/IClearingHouseActions.sol';
import { IClearingHouseStructures } from '../../interfaces/clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseEnums } from '../../interfaces/clearinghouse/IClearingHouseEnums.sol';
import { IClearingHouseOwnerActions } from '../../interfaces/clearinghouse/IClearingHouseOwnerActions.sol';
import { IClearingHouseSystemActions } from '../../interfaces/clearinghouse/IClearingHouseSystemActions.sol';

import { Multicall } from '../../utils/Multicall.sol';
import { OptimisticGasUsedClaim } from '../../utils/OptimisticGasUsedClaim.sol';

import { ClearingHouseView } from './ClearingHouseView.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouse is IClearingHouse, ClearingHouseView, Multicall, PausableUpgradeable, OptimisticGasUsedClaim {
    using SafeERC20 for IERC20;
    using Account for Account.Info;
    using AddressHelper for address;
    using AddressHelper for IERC20;
    using Protocol for Protocol.Info;
    using SignedMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    error NotRageTradeFactory();
    error ZeroAmount();

    modifier onlyRageTradeFactory() {
        if (rageTradeFactoryAddress != msg.sender) revert NotRageTradeFactory();
        _;
    }

    /**
        SYSTEM FUNCTIONS
     */

    function __initialize_ClearingHouse(
        address _rageTradeFactoryAddress,
        IERC20 _defaultCollateralToken,
        IOracle _defaultCollateralTokenOracle,
        IInsuranceFund _insuranceFund,
        IVQuote _vQuote,
        IOracle _nativeOracle
    ) external initializer {
        rageTradeFactoryAddress = _rageTradeFactoryAddress;
        protocol.settlementToken = _defaultCollateralToken;
        insuranceFund = _insuranceFund;
        nativeOracle = _nativeOracle;

        protocol.vQuote = _vQuote;

        _updateCollateralSettings(
            _defaultCollateralToken,
            CollateralSettings({ oracle: _defaultCollateralTokenOracle, twapDuration: 60, supported: true })
        );

        __Governable_init();
        __Pausable_init_unchained();
    }

    function registerPool(Pool calldata poolInfo) external onlyRageTradeFactory {
        uint32 poolId = address(poolInfo.vToken).truncate();

        // pool will not be registered twice by the rage trade factory
        assert(address(protocol.pools[poolId].vToken).isZero());

        protocol.pools[poolId] = poolInfo;
        emit PoolSettingsUpdated(poolId, poolInfo.settings);
    }

    /**
        ADMIN FUNCTIONS
     */

    function updateCollateralSettings(IERC20 cToken, CollateralSettings memory collateralSettings)
        external
        onlyGovernanceOrTeamMultisig
    {
        _updateCollateralSettings(cToken, collateralSettings);
    }

    function updatePoolSettings(uint32 poolId, PoolSettings calldata newSettings) public onlyGovernanceOrTeamMultisig {
        protocol.pools[poolId].settings = newSettings;
        emit PoolSettingsUpdated(poolId, newSettings);
    }

    function updateProtocolSettings(
        LiquidationParams calldata _liquidationParams,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _minRequiredMargin
    ) external onlyGovernanceOrTeamMultisig {
        protocol.liquidationParams = _liquidationParams;
        protocol.removeLimitOrderFee = _removeLimitOrderFee;
        protocol.minimumOrderNotional = _minimumOrderNotional;
        protocol.minRequiredMargin = _minRequiredMargin;
        emit ProtocolSettingsUpdated(
            _liquidationParams,
            _removeLimitOrderFee,
            _minimumOrderNotional,
            _minRequiredMargin
        );
    }

    function pause() external onlyGovernanceOrTeamMultisig {
        _pause();
    }

    function unpause() external onlyGovernanceOrTeamMultisig {
        _unpause();
    }

    /// @inheritdoc IClearingHouseOwnerActions
    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            uint256 wrapperFee = IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
            emit Account.ProtocolFeesWithdrawn(wrapperAddresses[i], wrapperFee);
            totalProtocolFee += wrapperFee;
        }
        protocol.settlementToken.safeTransfer(teamMultisig(), totalProtocolFee);
    }

    /**
        USER FUNCTIONS
     */

    /// @inheritdoc IClearingHouseActions
    function createAccount() public whenNotPaused returns (uint256 newAccountId) {
        newAccountId = numAccounts;
        numAccounts = newAccountId + 1; // SSTORE

        Account.Info storage newAccount = accounts[newAccountId];
        newAccount.owner = msg.sender;
        newAccount.id = uint96(newAccountId);

        emit AccountCreated(msg.sender, newAccountId);
    }

    /// @inheritdoc IClearingHouseActions
    function addMargin(
        uint256 accountId,
        uint32 collateralId,
        uint256 amount
    ) public whenNotPaused {
        Account.Info storage account = _getAccountAndCheckOwner(accountId);
        _addMargin(accountId, account, collateralId, amount);
    }

    function _getAccountAndCheckOwner(uint256 accountId) internal view returns (Account.Info storage account) {
        account = accounts[accountId];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);
    }

    // done
    function _addMargin(
        uint256 accountId,
        Account.Info storage account,
        uint32 collateralId,
        uint256 amount
    ) internal whenNotPaused {
        Collateral storage collateral = _checkCollateralIdAndGetInfo(collateralId, true);

        collateral.token.safeTransferFrom(msg.sender, address(this), amount);

        account.addMargin(collateralId, amount);

        emit MarginAdded(accountId, collateralId, amount);
    }

    /// @inheritdoc IClearingHouseActions
    function createAccountAndAddMargin(uint32 poolId, uint256 amount) external returns (uint256 newAccountId) {
        newAccountId = createAccount();
        addMargin(newAccountId, poolId, amount);
    }

    /// @inheritdoc IClearingHouseActions
    function removeMargin(
        uint256 accountId,
        uint32 collateralId,
        uint256 amount
    ) external whenNotPaused {
        Account.Info storage account = _getAccountAndCheckOwner(accountId);
        _removeMargin(accountId, account, collateralId, amount, true);
    }

    function _removeMargin(
        uint256 accountId,
        Account.Info storage account,
        uint32 collateralId,
        uint256 amount,
        bool checkMargin
    ) internal whenNotPaused {
        Collateral storage collateral = _checkCollateralIdAndGetInfo(collateralId, false);

        account.removeMargin(collateralId, amount, protocol, checkMargin);

        collateral.token.safeTransfer(msg.sender, amount);

        emit MarginRemoved(accountId, collateralId, amount);
    }

    /// @inheritdoc IClearingHouseActions
    function updateProfit(uint256 accountId, int256 amount) external whenNotPaused {
        Account.Info storage account = _getAccountAndCheckOwner(accountId);

        _updateProfit(account, amount, true);
    }

    function _updateProfit(
        Account.Info storage account,
        int256 amount,
        bool checkMargin
    ) internal whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        account.updateProfit(amount, protocol, checkMargin);
        if (amount > 0) {
            protocol.settlementToken.safeTransferFrom(msg.sender, address(this), uint256(amount));
        } else {
            protocol.settlementToken.safeTransfer(msg.sender, uint256(-amount));
        }
        emit Account.ProfitUpdated(account.id, amount);
    }

    /// @inheritdoc IClearingHouseActions
    function swapToken(
        uint256 accountId,
        uint32 poolId,
        SwapParams memory swapParams
    ) external whenNotPaused returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        Account.Info storage account = _getAccountAndCheckOwner(accountId);
        return _swapToken(account, poolId, swapParams, true);
    }

    function _swapToken(
        Account.Info storage account,
        uint32 poolId,
        SwapParams memory swapParams,
        bool checkMargin
    ) internal whenNotPaused returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        _checkPoolId(poolId);

        (vTokenAmountOut, vQuoteAmountOut) = account.swapToken(poolId, swapParams, protocol, checkMargin);

        uint256 vQuoteAmountOutAbs = uint256(vQuoteAmountOut.abs());
        if (vQuoteAmountOutAbs < protocol.minimumOrderNotional) revert LowNotionalValue(vQuoteAmountOutAbs);

        if (swapParams.sqrtPriceLimit != 0 && !swapParams.isPartialAllowed) {
            if (
                !((swapParams.isNotional && vQuoteAmountOut.abs() == swapParams.amount.abs()) ||
                    (!swapParams.isNotional && vTokenAmountOut.abs() == swapParams.amount.abs()))
            ) revert SlippageBeyondTolerance();
        }
    }

    /// @inheritdoc IClearingHouseActions
    function updateRangeOrder(
        uint256 accountId,
        uint32 poolId,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external whenNotPaused returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        Account.Info storage account = _getAccountAndCheckOwner(accountId);

        return _updateRangeOrder(account, poolId, liquidityChangeParams, true);
    }

    function _updateRangeOrder(
        Account.Info storage account,
        uint32 poolId,
        LiquidityChangeParams memory liquidityChangeParams,
        bool checkMargin
    ) internal whenNotPaused returns (int256 vTokenAmountOut, int256 vQuoteAmountOut) {
        _checkPoolId(poolId);

        if (liquidityChangeParams.sqrtPriceCurrent != 0) {
            _checkSlippage(poolId, liquidityChangeParams.sqrtPriceCurrent, liquidityChangeParams.slippageToleranceBps);
        }

        (vTokenAmountOut, vQuoteAmountOut) = account.liquidityChange(
            poolId,
            liquidityChangeParams,
            protocol,
            checkMargin
        );

        // TODO this lib is being used here causing bytecode size to increase, remove it
        uint256 notionalValueAbs = uint256(
            VTokenPositionSet.getNotionalValue(poolId, vTokenAmountOut, vQuoteAmountOut, protocol)
        );

        if (notionalValueAbs < protocol.minimumOrderNotional) revert LowNotionalValue(notionalValueAbs);
    }

    /// @inheritdoc IClearingHouseActions
    function removeLimitOrder(
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper
    ) external {
        _removeLimitOrder(accountId, poolId, tickLower, tickUpper, 0);
    }

    /// @inheritdoc IClearingHouseActions
    function liquidateLiquidityPositions(uint256 accountId) external {
        _liquidateLiquidityPositions(accountId, 0);
    }

    /// @inheritdoc IClearingHouseActions
    function liquidateTokenPosition(
        uint256 liquidatorAccountId,
        uint256 targetAccountId,
        uint32 poolId,
        uint16 liquidationBps
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments) {
        return
            _liquidateTokenPosition(
                accounts[liquidatorAccountId],
                accounts[targetAccountId],
                poolId,
                liquidationBps,
                0
            );
    }

    /**
        MULTICALL
     */

    function multicallWithSingleMarginCheck(uint256 accountId, MulticallOperation[] calldata operations)
        external
        returns (bytes[] memory results)
    {
        results = new bytes[](operations.length);

        Account.Info storage account = _getAccountAndCheckOwner(accountId);

        bool checkProfit = false;

        for (uint256 i = 0; i < operations.length; i++) {
            if (operations[i].operationType == MulticallOperationType.ADD_MARGIN) {
                // ADD_MARGIN
                (uint32 collateralId, uint256 amount) = abi.decode(operations[i].data, (uint32, uint256));
                _addMargin(accountId, account, collateralId, amount);
            } else if (operations[i].operationType == MulticallOperationType.REMOVE_MARGIN) {
                // REMOVE_MARGIN
                (uint32 collateralId, uint256 amount) = abi.decode(operations[i].data, (uint32, uint256));
                _removeMargin(accountId, account, collateralId, amount, false);
            } else if (operations[i].operationType == MulticallOperationType.UPDATE_PROFIT) {
                // UPDATE_PROFIT
                int256 amount = abi.decode(operations[i].data, (int256));
                _updateProfit(account, amount, false);
                checkProfit = true;
            } else if (operations[i].operationType == MulticallOperationType.SWAP_TOKEN) {
                // SWAP_TOKEN
                (uint32 poolId, SwapParams memory sp) = abi.decode(operations[i].data, (uint32, SwapParams));
                (int256 vTokenAmountOut, int256 vQuoteAmountOut) = _swapToken(account, poolId, sp, false);
                results[i] = abi.encode(vTokenAmountOut, vQuoteAmountOut);
            } else if (operations[i].operationType == MulticallOperationType.UPDATE_RANGE_ORDER) {
                // UPDATE_RANGE_ORDER
                (uint32 poolId, LiquidityChangeParams memory lcp) = abi.decode(
                    operations[i].data,
                    (uint32, LiquidityChangeParams)
                );
                (int256 vTokenAmountOut, int256 vQuoteAmountOut) = _updateRangeOrder(account, poolId, lcp, false);
                results[i] = abi.encode(vTokenAmountOut, vQuoteAmountOut);
            } else if (operations[i].operationType == MulticallOperationType.REMOVE_LIMIT_ORDER) {
                // REMOVE_LIMIT_ORDER
                (uint32 poolId, int24 tickLower, int24 tickUpper, uint256 limitOrderFeeAndFixFee) = abi.decode(
                    operations[i].data,
                    (uint32, int24, int24, uint256)
                );
                _removeLimitOrder(accountId, poolId, tickLower, tickUpper, limitOrderFeeAndFixFee);
            } else if (operations[i].operationType == MulticallOperationType.LIQUIDATE_LIQUIDITY_POSITIONS) {
                // LIQUIDATE_LIQUIDITY_POSITIONS
                _liquidateLiquidityPositions(accountId, 0);
            } else if (operations[i].operationType == MulticallOperationType.LIQUIDATE_TOKEN_POSITION) {
                // LIQUIDATE_TOKEN_POSITION
                (uint256 targetAccountId, uint32 poolId, uint16 liquidationBps) = abi.decode(
                    operations[i].data,
                    (uint256, uint32, uint16)
                );
                results[i] = abi.encode(
                    _liquidateTokenPosition(accounts[accountId], accounts[targetAccountId], poolId, liquidationBps, 0)
                );
            } else {
                revert InvalidMulticallOperationType(operations[i].operationType);
            }
        }

        // after all the operations are done, check the margin requirements
        if (checkProfit) account.checkIfProfitAvailable(protocol);
        account.checkIfMarginAvailable(true, protocol);

        return results;
    }

    /**
        ALTERNATE LIQUIDATION METHODS FOR FIX FEE CLAIM
     */

    function removeLimitOrderWithGasClaim(
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) external checkGasUsedClaim(gasComputationUnitsClaim) returns (uint256 keeperFee) {
        Calldata.limit(4 + 5 * 0x20);
        return _removeLimitOrder(accountId, poolId, tickLower, tickUpper, gasComputationUnitsClaim);
    }

    function liquidateLiquidityPositionsWithGasClaim(uint256 accountId, uint256 gasComputationUnitsClaim)
        external
        checkGasUsedClaim(gasComputationUnitsClaim)
        returns (int256 keeperFee)
    {
        Calldata.limit(4 + 2 * 0x20);
        return _liquidateLiquidityPositions(accountId, gasComputationUnitsClaim);
    }

    function liquidateTokenPositionWithGasClaim(
        uint256 liquidatorAccountId,
        uint256 targetAccountId,
        uint32 poolId,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    )
        external
        checkGasUsedClaim(gasComputationUnitsClaim)
        returns (BalanceAdjustments memory liquidatorBalanceAdjustments)
    {
        Calldata.limit(4 + 5 * 0x20);
        /// @dev liquidator account gets benefit, hence ownership is not required
        return
            // TODO see if we really need to evaluate storage pointers and pass down from here
            _liquidateTokenPosition(
                accounts[liquidatorAccountId],
                accounts[targetAccountId],
                poolId,
                liquidationBps,
                gasComputationUnitsClaim
            );
    }

    /**
        INTERNAL HELPERS
     */

    function _checkSlippage(
        uint32 poolId,
        uint160 sqrtPriceToCheck,
        uint16 slippageToleranceBps
    ) internal view {
        uint160 sqrtPriceCurrent = protocol.getVirtualCurrentSqrtPriceX96For(poolId);
        uint160 diff = sqrtPriceCurrent > sqrtPriceToCheck
            ? sqrtPriceCurrent - sqrtPriceToCheck
            : sqrtPriceToCheck - sqrtPriceCurrent;
        if (diff > (slippageToleranceBps * sqrtPriceToCheck) / 1e4) {
            revert SlippageBeyondTolerance();
        }
    }

    function _checkCollateralIdAndGetInfo(uint32 collateralId, bool checkSupported)
        internal
        view
        returns (Collateral storage collateral)
    {
        collateral = protocol.collaterals[collateralId];
        if (collateral.token.isZero()) revert UninitializedToken(collateralId); // TODO change to UninitializedCollateral
        if (checkSupported && !collateral.settings.supported) revert UnsupportedCToken(address(collateral.token)); // TODO change this to collateralId
    }

    function _checkPoolId(uint32 poolId) internal view {
        IVToken vToken = protocol.pools[poolId].vToken; // TODO remove this line
        if (address(vToken).isZero()) revert UninitializedToken(poolId); // TODO change to UninitializedVToken
        if (!protocol.pools[poolId].settings.supported) revert UnsupportedVToken(vToken); // TODO change this to UnsupportedPool
    }

    function _liquidateLiquidityPositions(uint256 accountId, uint256 gasComputationUnitsClaim)
        internal
        whenNotPaused
        returns (int256 keeperFee)
    {
        Account.Info storage account = accounts[accountId];
        int256 insuranceFundFee;
        (keeperFee, insuranceFundFee) = account.liquidateLiquidityPositions(
            _getFixFee(gasComputationUnitsClaim),
            protocol
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        if (keeperFee <= 0) revert KeeperFeeNotPositive(keeperFee);
        protocol.settlementToken.safeTransfer(msg.sender, uint256(keeperFee));
        _transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidityPositionsLiquidated(accountId, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    // TODO move this to Account library
    // TODO see order of the arguments, in account lib targetAccount is first and vice versa is here
    function _liquidateTokenPosition(
        Account.Info storage liquidatorAccount,
        Account.Info storage targetAccount,
        uint32 poolId,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    ) internal whenNotPaused returns (BalanceAdjustments memory liquidatorBalanceAdjustments) {
        if (liquidationBps > 10000) revert InvalidTokenLiquidationParameters();

        _checkPoolId(poolId); // TODO refactor this method
        int256 insuranceFundFee;
        (insuranceFundFee, liquidatorBalanceAdjustments) = targetAccount.liquidateTokenPosition(
            liquidatorAccount,
            liquidationBps,
            poolId,
            _getFixFee(gasComputationUnitsClaim),
            protocol,
            true
        );

        _transferInsuranceFundFee(insuranceFundFee);
    }

    function _removeLimitOrder(
        uint256 accountId,
        uint32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) internal whenNotPaused returns (uint256 keeperFee) {
        Account.Info storage account = accounts[accountId];

        _checkPoolId(poolId);
        keeperFee = protocol.removeLimitOrderFee + _getFixFee(gasComputationUnitsClaim);

        account.removeLimitOrder(poolId, tickLower, tickUpper, keeperFee, protocol);

        protocol.settlementToken.safeTransfer(msg.sender, keeperFee);
    }

    function _transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            protocol.settlementToken.safeTransfer(address(insuranceFund), uint256(insuranceFundFee));
        } else {
            insuranceFund.claim(uint256(-insuranceFundFee));
        }
    }

    function _updateCollateralSettings(IERC20 collateralToken, CollateralSettings memory collateralSettings) internal {
        uint32 collateralId = collateralToken.truncate();

        // doesn't allow zero address as a collateral token
        if (collateralToken.isZero()) revert InvalidCollateralAddress(address(0));

        // doesn't allow owner to change the cToken address when updating settings, once it's truncated previously
        // TODO remove so many address() castings
        if (
            !protocol.collaterals[collateralId].token.isZero() &&
            !protocol.collaterals[collateralId].token.eq(collateralToken)
        ) {
            revert IncorrectCollateralAddress(collateralToken, protocol.collaterals[collateralId].token);
        }

        protocol.collaterals[collateralId] = Collateral(collateralToken, collateralSettings);

        emit CollateralSettingsUpdated(collateralToken, collateralSettings);
    }

    /// @notice Gets fix fee
    /// @dev Allowed to be overriden for specific chain implementations
    /// @return fixFee amount of fixFee in base
    function _getFixFee(uint256) internal view virtual returns (uint256 fixFee) {
        return 0;
    }
}
