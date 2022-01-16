//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { Account } from '../../libraries/Account.sol';
import { LiquidityPositionSet } from '../../libraries/LiquidityPositionSet.sol';
import { VTokenPositionSet } from '../../libraries/VTokenPositionSet.sol';
import { SignedMath } from '../../libraries/SignedMath.sol';
import { VTokenAddress, VTokenLib } from '../../libraries/VTokenLib.sol';
import { RTokenLib } from '../../libraries/RTokenLib.sol';
// import { Calldata } from './libraries/Calldata.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVBase } from '../../interfaces/IVBase.sol';

import { OptimisticGasUsedClaim } from '../../utils/OptimisticGasUsedClaim.sol';

import { ClearingHouseStorage } from './ClearingHouseStorage.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouse is IClearingHouse, OptimisticGasUsedClaim, ClearingHouseStorage {
    using SafeERC20 for IERC20;
    using Account for Account.UserInfo;
    using VTokenLib for VTokenAddress;
    using SignedMath for int256;
    using RTokenLib for RTokenLib.RToken;

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

    function ClearingHouse__init(
        address _rageTradeFactoryAddress,
        IERC20 _rBase,
        IInsuranceFund _insuranceFund,
        IVBase _vBase,
        IOracle _nativeOracle
    ) external initializer {
        rageTradeFactoryAddress = _rageTradeFactoryAddress;
        rBase = _rBase;
        insuranceFund = _insuranceFund;
        nativeOracle = _nativeOracle;

        protocol.vBase = _vBase;

        Governable__init();
    }

    function registerPool(address full, RageTradePool calldata rageTradePool) external onlyRageTradeFactory {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(protocol.vTokenAddresses[truncated].eq(address(0)));

        protocol.vTokenAddresses[truncated] = vTokenAddress;
        protocol.pools[vTokenAddress] = rageTradePool;
    }

    function initRealToken(address realToken) external onlyRageTradeFactory {
        realTokenInitilized[realToken] = true;
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

    function updateSupportedVTokens(VTokenAddress add, bool status) external onlyGovernanceOrTeamMultisig {
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

    function updateRageTradePoolSettings(VTokenAddress vTokenAddress, RageTradePoolSettings calldata newSettings)
        public
        onlyGovernanceOrTeamMultisig
    {
        protocol.pools[vTokenAddress].settings = newSettings;
    }

    /// @inheritdoc IClearingHouse
    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            uint256 wrapperFee = IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
            emit Account.ProtocolFeeWithdrawm(wrapperAddresses[i], wrapperFee);
            totalProtocolFee += wrapperFee;
        }
        rBase.transfer(teamMultisig(), totalProtocolFee);
    }

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

        RTokenLib.RToken storage rToken = _getRTokenWithChecks(rTokenTruncatedAddress);

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

        RTokenLib.RToken storage rToken = _getRTokenWithChecks(rTokenTruncatedAddress);

        account.removeMargin(rToken.tokenAddress, amount, protocol);

        IERC20(rToken.realToken()).safeTransfer(msg.sender, amount);

        emit Account.WithdrawMargin(accountNo, rToken.tokenAddress, amount);
    }

    /// @inheritdoc IClearingHouse
    function removeProfit(uint256 accountNo, uint256 amount) external notPaused {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        account.removeProfit(amount, protocol);
        rBase.transfer(msg.sender, amount);

        emit Account.WithdrawProfit(accountNo, amount);
    }

    /// @inheritdoc IClearingHouse
    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        VTokenPositionSet.SwapParams memory swapParams
    ) external notPaused returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = _getVTokenAddressWithChecks(vTokenTruncatedAddress);

        (vTokenAmountOut, vBaseAmountOut) = account.swapToken(vTokenAddress, swapParams, protocol);

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
        LiquidityPositionSet.LiquidityChangeParams calldata liquidityChangeParams
    ) external notPaused returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.UserInfo storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = _getVTokenAddressWithChecks(vTokenTruncatedAddress);

        if (liquidityChangeParams.sqrtPriceCurrent != 0) {
            _checkSlippage(
                vTokenAddress,
                liquidityChangeParams.sqrtPriceCurrent,
                liquidityChangeParams.slippageToleranceBps
            );
        }

        (vTokenAmountOut, vBaseAmountOut) = account.liquidityChange(vTokenAddress, liquidityChangeParams, protocol);

        uint256 notionalValueAbs = uint256(
            VTokenPositionSet.getNotionalValue(vTokenAddress, vTokenAmountOut, vBaseAmountOut, protocol)
        );

        if (notionalValueAbs < protocol.minimumOrderNotional) revert LowNotionalValue(notionalValueAbs);
    }

    /// @inheritdoc IClearingHouse
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external returns (uint256 keeperFee) {
        return _removeLimitOrder(accountNo, vTokenTruncatedAddress, tickLower, tickUpper, 0);
    }

    /// @inheritdoc IClearingHouse
    function liquidateLiquidityPositions(uint256 accountNo) external returns (int256 keeperFee) {
        return _liquidateLiquidityPositions(accountNo, 0);
    }

    /// @inheritdoc IClearingHouse
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) external returns (Account.BalanceAdjustments memory liquidatorBalanceAdjustments) {
        return _liquidateTokenPosition(liquidatorAccountNo, accountNo, vTokenTruncatedAddress, liquidationBps, 0);
    }

    /**
        INTERNAL HELPERS
     */

    function _checkSlippage(
        VTokenAddress vTokenAddress,
        uint160 sqrtPriceToCheck,
        uint16 slippageToleranceBps
    ) internal view {
        uint160 sqrtPriceCurrent = vTokenAddress.getVirtualCurrentSqrtPriceX96(protocol);
        uint160 diff = sqrtPriceCurrent > sqrtPriceToCheck
            ? sqrtPriceCurrent - sqrtPriceToCheck
            : sqrtPriceToCheck - sqrtPriceCurrent;
        if (diff > (slippageToleranceBps * sqrtPriceToCheck) / 1e4) {
            revert SlippageBeyondTolerance();
        }
    }

    function _getRTokenWithChecks(uint32 rTokenTruncatedAddress)
        internal
        view
        returns (RTokenLib.RToken storage rToken)
    {
        rToken = protocol.rTokens[rTokenTruncatedAddress];
        if (rToken.eq(address(0))) revert UninitializedToken(rTokenTruncatedAddress);
        if (!supportedDeposits[rToken.tokenAddress]) revert UnsupportedRToken(rToken.tokenAddress);
    }

    function _getVTokenAddressWithChecks(uint32 vTokenTruncatedAddress)
        internal
        view
        returns (VTokenAddress vTokenAddress)
    {
        vTokenAddress = protocol.vTokenAddresses[vTokenTruncatedAddress];
        if (vTokenAddress.eq(address(0))) revert UninitializedToken(vTokenTruncatedAddress);
        if (!supportedVTokens[vTokenAddress]) revert UnsupportedVToken(vTokenAddress);
    }

    function _liquidateLiquidityPositions(uint256 accountNo, uint256 gasComputationUnitsClaim)
        internal
        notPaused
        returns (int256 keeperFee)
    {
        // Calldata.limit(0x4 + 2 * 0x20);

        Account.UserInfo storage account = accounts[accountNo];
        int256 insuranceFundFee;
        (keeperFee, insuranceFundFee) = account.liquidateLiquidityPositions(
            getFixFee(gasComputationUnitsClaim),
            protocol
        );
        int256 accountFee = keeperFee + insuranceFundFee;

        rBase.transfer(msg.sender, uint256(keeperFee));
        _transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    function _liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps,
        uint256 gasComputationUnitsClaim
    ) internal notPaused returns (Account.BalanceAdjustments memory liquidatorBalanceAdjustments) {
        // Calldata.limit(0x4 + 5 * 0x20);

        if (liquidationBps > 10000) revert InvalidTokenLiquidationParameters();
        Account.UserInfo storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = _getVTokenAddressWithChecks(vTokenTruncatedAddress);
        int256 insuranceFundFee;
        (insuranceFundFee, liquidatorBalanceAdjustments) = account.liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            liquidationBps,
            vTokenAddress,
            getFixFee(gasComputationUnitsClaim),
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
        // TODO remove
        // Calldata.limit(0x4 + 5 * 0x20);

        Account.UserInfo storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = _getVTokenAddressWithChecks(vTokenTruncatedAddress);
        keeperFee = protocol.removeLimitOrderFee + getFixFee(gasComputationUnitsClaim);

        account.removeLimitOrder(vTokenAddress, tickLower, tickUpper, keeperFee, protocol);

        rBase.transfer(msg.sender, keeperFee);
        // emit Account.LiqudityChange(accountNo, tickLower, tickUpper, liquidityDelta, 0, 0, 0);
    }

    function _transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            rBase.transfer(address(insuranceFund), uint256(insuranceFundFee));
        } else {
            insuranceFund.claim(uint256(-insuranceFundFee));
        }
    }

    /**
        VIEW FUNCTIONS
     */

    /// @notice Gets fix fee
    /// @dev Allowed to be overriden for specific chain implementations
    /// @return fixFee amount of fixFee in base
    function getFixFee(uint256) public view virtual returns (uint256 fixFee) {
        return 0;
    }

    function getTwapSqrtPricesForSetDuration(VTokenAddress vTokenAddress)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        realPriceX128 = vTokenAddress.getRealTwapPriceX128(protocol);
        virtualPriceX128 = vTokenAddress.getVirtualTwapPriceX128(protocol);
    }

    function isRealTokenAlreadyInitilized(address realToken) external view returns (bool) {
        return realTokenInitilized[realToken];
    }

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool) {
        return protocol.vTokenAddresses[truncated].eq(address(0));
    }

    function rageTradePools(VTokenAddress vTokenAddress) public view returns (RageTradePool memory rageTradePool) {
        return protocol.pools[vTokenAddress];
    }
}
