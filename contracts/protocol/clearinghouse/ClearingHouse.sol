//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { SafeCast } from '@uniswap/v3-core-0.8-support/contracts/libraries/SafeCast.sol';

import { Account } from '../../libraries/Account.sol';
import { LiquidityPositionSet } from '../../libraries/LiquidityPositionSet.sol';
import { VTokenPositionSet } from '../../libraries/VTokenPositionSet.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { VTokenLib } from '../../libraries/VTokenLib.sol';
import { RTokenLib } from '../../libraries/RTokenLib.sol';
import { Calldata } from '../../libraries/Calldata.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVBase } from '../../interfaces/IVBase.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

import { OptimisticGasUsedClaim } from '../../utils/OptimisticGasUsedClaim.sol';

import { ClearingHouseView } from './ClearingHouseView.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouse is IClearingHouse, ClearingHouseView, OptimisticGasUsedClaim {
    using SafeERC20 for IERC20;
    using Account for Account.UserInfo;
    using VTokenLib for IVToken;
    using SignedMath for int256;
    using RTokenLib for RTokenLib.RToken;
    using SafeCast for uint256;
    using SafeCast for int256;

    error Paused();
    error NotRageTradeFactory();

    modifier onlyRageTradeFactory() {
        if (rageTradeFactoryAddress != msg.sender) revert NotRageTradeFactory();
        _;
    }

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    /**
        PLATFORM FUNCTIONS
     */

    function __ClearingHouse_init(
        address _rageTradeFactoryAddress,
        IERC20 _rBase,
        IInsuranceFund _insuranceFund,
        IVBase _vBase,
        IOracle _nativeOracle
    ) external initializer {
        rageTradeFactoryAddress = _rageTradeFactoryAddress;
        protocol.rBase = _rBase;
        insuranceFund = _insuranceFund;
        nativeOracle = _nativeOracle;

        protocol.vBase = _vBase;

        __Governable_init();
    }

    function registerPool(address full, RageTradePool calldata rageTradePool) external onlyRageTradeFactory {
        IVToken vToken = IVToken(full);
        uint32 truncated = vToken.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(protocol.vTokens[truncated].eq(address(0)));

        protocol.vTokens[truncated] = vToken;
        protocol.pools[vToken] = rageTradePool;
    }

    /**
        ADMIN FUNCTIONS
     */

    function addCollateralSupport(
        address rTokenAddress,
        address oracleAddress,
        uint32 twapDuration
    ) external onlyGovernanceOrTeamMultisig {
        RTokenLib.RToken memory token = RTokenLib.RToken(rTokenAddress, oracleAddress, twapDuration);
        protocol.rTokens[uint32(uint160(token.tokenAddress))] = token;
    }

    function updateSupportedVTokens(IVToken add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedVTokens[add] = status;
    }

    function updateSupportedDeposits(address add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedDeposits[add] = status;
    }

    function setPaused(bool _pause) external onlyGovernanceOrTeamMultisig {
        paused = _pause;
    }

    // TODO: rename to setGlobalSettings
    function setPlatformParameters(
        Account.LiquidationParams calldata _liquidationParams,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _minRequiredMargin
    ) external onlyGovernanceOrTeamMultisig {
        protocol.liquidationParams = _liquidationParams;
        protocol.removeLimitOrderFee = _removeLimitOrderFee;
        protocol.minimumOrderNotional = _minimumOrderNotional;
        protocol.minRequiredMargin = _minRequiredMargin;
    }

    function updateRageTradePoolSettings(IVToken vToken, RageTradePoolSettings calldata newSettings)
        public
        onlyGovernanceOrTeamMultisig
    {
        protocol.pools[vToken].settings = newSettings;
    }

    /// @inheritdoc IClearingHouse
    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            uint256 wrapperFee = IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
            emit Account.ProtocolFeeWithdrawm(wrapperAddresses[i], wrapperFee);
            totalProtocolFee += wrapperFee;
        }
        protocol.rBase.safeTransfer(teamMultisig(), totalProtocolFee);
    }

    /**
        USER FUNCTIONS
     */

    /// @inheritdoc IClearingHouse
    function createAccount() external notPaused returns (uint256 newAccountId) {
        newAccountId = numAccounts;
        numAccounts = newAccountId + 1; // SSTORE

        Account.UserInfo storage newAccount = accounts[newAccountId];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = newAccountId;

        emit Account.AccountCreated(msg.sender, newAccountId);
    }

    /// @inheritdoc IClearingHouse
    function addMargin(
        uint256 accountNo,
        uint32 rTokenTruncatedAddress,
        uint256 amount
    ) external notPaused {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        RTokenLib.RToken storage rToken = _getRTokenWithChecks(rTokenTruncatedAddress, true);

        IERC20(rToken.realToken()).safeTransferFrom(msg.sender, address(this), amount);

        account.addMargin(rToken.tokenAddress, amount);

        emit Account.DepositMargin(accountNo, rToken.tokenAddress, amount);
    }

    /// @inheritdoc IClearingHouse
    function removeMargin(
        uint256 accountNo,
        uint32 rTokenTruncatedAddress,
        uint256 amount
    ) external notPaused {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        RTokenLib.RToken storage rToken = _getRTokenWithChecks(rTokenTruncatedAddress, false);

        account.removeMargin(rToken.tokenAddress, amount, protocol);

        IERC20(rToken.realToken()).safeTransfer(msg.sender, amount);

        emit Account.WithdrawMargin(accountNo, rToken.tokenAddress, amount);
    }

    /// @inheritdoc IClearingHouse
    function updateProfit(uint256 accountNo, int256 amount) external notPaused {
        require(amount != 0, '!amount');
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        account.updateProfit(amount, protocol);
        if (amount > 0) {
            protocol.rBase.safeTransferFrom(msg.sender, address(this), uint256(amount));
        } else {
            protocol.rBase.safeTransfer(msg.sender, uint256(-amount));
        }
        emit Account.UpdateProfit(accountNo, amount);
    }

    /// @inheritdoc IClearingHouse
    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external notPaused returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        IVToken vToken = _getIVTokenWithChecks(vTokenTruncatedAddress);

        (vTokenAmountOut, vBaseAmountOut) = account.swapToken(vToken, swapParams, protocol);

        uint256 vBaseAmountOutAbs = uint256(vBaseAmountOut.abs());
        if (vBaseAmountOutAbs < protocol.minimumOrderNotional) revert LowNotionalValue(vBaseAmountOutAbs);

        if (swapParams.sqrtPriceLimit != 0 && !swapParams.isPartialAllowed) {
            if (
                !((swapParams.isNotional && vBaseAmountOut.abs() == swapParams.amount.abs()) ||
                    (!swapParams.isNotional && vTokenAmountOut.abs() == swapParams.amount.abs()))
            ) revert SlippageBeyondTolerance();
        }
    }

    /// @inheritdoc IClearingHouse
    function updateRangeOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        LiquidityChangeParams calldata liquidityChangeParams
    ) external notPaused returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        IVToken vToken = _getIVTokenWithChecks(vTokenTruncatedAddress);

        if (liquidityChangeParams.sqrtPriceCurrent != 0) {
            _checkSlippage(vToken, liquidityChangeParams.sqrtPriceCurrent, liquidityChangeParams.slippageToleranceBps);
        }

        (vTokenAmountOut, vBaseAmountOut) = account.liquidityChange(vToken, liquidityChangeParams, protocol);

        uint256 notionalValueAbs = uint256(
            VTokenPositionSet.getNotionalValue(vToken, vTokenAmountOut, vBaseAmountOut, protocol)
        );

        if (notionalValueAbs < protocol.minimumOrderNotional) revert LowNotionalValue(notionalValueAbs);
    }

    /// @inheritdoc IClearingHouse
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external {
        _removeLimitOrder(accountNo, vTokenTruncatedAddress, tickLower, tickUpper, 0);
    }

    /// @inheritdoc IClearingHouse
    function liquidateLiquidityPositions(uint256 accountNo) external {
        _liquidateLiquidityPositions(accountNo, 0);
    }

    /// @inheritdoc IClearingHouse
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external returns (BalanceAdjustments memory liquidatorBalanceAdjustments) {
        return _liquidateTokenPosition(liquidatorAccountNo, accountNo, vTokenTruncatedAddress, liquidationBps, 0);
    }

    /**
        ALTERNATE LIQUIDATION METHODS FOR FIX FEE CLAIM
     */

    function removeLimitOrderWithGasClaim(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) external checkGasUsedClaim(gasComputationUnitsClaim) returns (uint256 keeperFee) {
        Calldata.limit(4 + 5 * 0x20);
        return _removeLimitOrder(accountNo, vTokenTruncatedAddress, tickLower, tickUpper, gasComputationUnitsClaim);
    }

    function liquidateLiquidityPositionsWithGasClaim(uint256 accountNo, uint256 gasComputationUnitsClaim)
        external
        checkGasUsedClaim(gasComputationUnitsClaim)
        returns (int256 keeperFee)
    {
        Calldata.limit(4 + 2 * 0x20);
        return _liquidateLiquidityPositions(accountNo, gasComputationUnitsClaim);
    }

    function liquidateTokenPositionWithGasClaim(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    )
        external
        checkGasUsedClaim(gasComputationUnitsClaim)
        returns (BalanceAdjustments memory liquidatorBalanceAdjustments)
    {
        Calldata.limit(4 + 5 * 0x20);
        return
            _liquidateTokenPosition(
                liquidatorAccountNo,
                accountNo,
                vTokenTruncatedAddress,
                liquidationBps,
                gasComputationUnitsClaim
            );
    }

    /**
        INTERNAL HELPERS
     */

    function _checkSlippage(
        IVToken vToken,
        uint160 sqrtPriceToCheck,
        uint16 slippageToleranceBps
    ) internal view {
        uint160 sqrtPriceCurrent = vToken.getVirtualCurrentSqrtPriceX96(protocol);
        uint160 diff = sqrtPriceCurrent > sqrtPriceToCheck
            ? sqrtPriceCurrent - sqrtPriceToCheck
            : sqrtPriceToCheck - sqrtPriceCurrent;
        if (diff > (slippageToleranceBps * sqrtPriceToCheck) / 1e4) {
            revert SlippageBeyondTolerance();
        }
    }

    function _getRTokenWithChecks(uint32 rTokenTruncatedAddress, bool checkSupported)
        internal
        view
        returns (RTokenLib.RToken storage rToken)
    {
        rToken = protocol.rTokens[rTokenTruncatedAddress];
        if (rToken.eq(address(0))) revert UninitializedToken(rTokenTruncatedAddress);
        if (checkSupported && !supportedDeposits[rToken.tokenAddress]) revert UnsupportedRToken(rToken.tokenAddress);
    }

    function _getIVTokenWithChecks(uint32 vTokenTruncatedAddress) internal view returns (IVToken vToken) {
        vToken = protocol.vTokens[vTokenTruncatedAddress];
        if (vToken.eq(address(0))) revert UninitializedToken(vTokenTruncatedAddress);
        if (!supportedVTokens[vToken]) revert UnsupportedVToken(vToken);
    }

    function _liquidateLiquidityPositions(uint256 accountNo, uint256 gasComputationUnitsClaim)
        internal
        notPaused
        returns (int256 keeperFee)
    {
        Account.UserInfo storage account = accounts[accountNo];
        int256 insuranceFundFee;
        (keeperFee, insuranceFundFee) = account.liquidateLiquidityPositions(
            _getFixFee(gasComputationUnitsClaim),
            protocol
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        require(keeperFee > 0, 'negative keeper fee');
        protocol.rBase.safeTransfer(msg.sender, uint256(keeperFee));
        _transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    function _liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    ) internal notPaused returns (BalanceAdjustments memory liquidatorBalanceAdjustments) {
        if (liquidationBps > 10000) revert InvalidTokenLiquidationParameters();
        Account.UserInfo storage account = accounts[accountNo];

        IVToken vToken = _getIVTokenWithChecks(vTokenTruncatedAddress);
        int256 insuranceFundFee;
        (insuranceFundFee, liquidatorBalanceAdjustments) = account.liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            liquidationBps,
            vToken,
            _getFixFee(gasComputationUnitsClaim),
            protocol
        );

        _transferInsuranceFundFee(insuranceFundFee);
    }

    function _removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper,
        uint256 gasComputationUnitsClaim
    ) internal notPaused returns (uint256 keeperFee) {
        Account.UserInfo storage account = accounts[accountNo];

        IVToken vToken = _getIVTokenWithChecks(vTokenTruncatedAddress);
        keeperFee = protocol.removeLimitOrderFee + _getFixFee(gasComputationUnitsClaim);

        account.removeLimitOrder(vToken, tickLower, tickUpper, keeperFee, protocol);

        protocol.rBase.safeTransfer(msg.sender, keeperFee);
        // emit Account.LiqudityChange(accountNo, tickLower, tickUpper, liquidityDelta, 0, 0, 0);
    }

    function _transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            protocol.rBase.safeTransfer(address(insuranceFund), uint256(insuranceFundFee));
        } else {
            insuranceFund.claim(uint256(-insuranceFundFee));
        }
    }

    /// @notice Gets fix fee
    /// @dev Allowed to be overriden for specific chain implementations
    /// @return fixFee amount of fixFee in base
    function _getFixFee(uint256) internal view virtual returns (uint256 fixFee) {
        return 0;
    }
}
