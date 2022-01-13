//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { Account, LiquidityChangeParams, LiquidationParams, SwapParams, VTokenPositionSet } from './libraries/Account.sol';
import { LimitOrderType } from './libraries/LiquidityPosition.sol';
import { ClearingHouseStorage } from './ClearingHouseStorage.sol';
import { IClearingHouse } from './interfaces/IClearingHouse.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { VTokenAddress, VTokenLib } from './libraries/VTokenLib.sol';
import { IInsuranceFund } from './interfaces/IInsuranceFund.sol';
import { IVPoolWrapper } from './interfaces/IVPoolWrapper.sol';
import { SignedMath } from './libraries/SignedMath.sol';

import { console } from 'hardhat/console.sol';

contract ClearingHouse is IClearingHouse, ClearingHouseStorage {
    using SafeERC20 for IERC20;
    using Account for Account.Info;
    using VTokenLib for VTokenAddress;
    using SignedMath for int256;

    function ClearingHouse__init(
        address _rageTradeFactory,
        address _realBase,
        address _insuranceFundAddress,
        address _vBaseAddress
    ) public initializer {
        rageTradeFactory = _rageTradeFactory;
        realBase = _realBase;
        insuranceFundAddress = _insuranceFundAddress;

        accountStorage.vBaseAddress = _vBaseAddress;

        Governable__init();
    }

    function checkSlippage(
        VTokenAddress vTokenAddress,
        uint160 sqrtPriceToCheck,
        uint16 slippageToleranceBps
    ) internal view {
        uint160 sqrtPriceCurrent = vTokenAddress.getVirtualCurrentSqrtPriceX96(accountStorage);
        uint160 diff = sqrtPriceCurrent > sqrtPriceToCheck
            ? sqrtPriceCurrent - sqrtPriceToCheck
            : sqrtPriceToCheck - sqrtPriceCurrent;
        if ((slippageToleranceBps * sqrtPriceToCheck) / 1e4 > diff) {
            revert SlippageBeyondTolerance();
        }
    }

    function getTokenAddressWithChecks(uint32 vTokenTruncatedAddress, bool isDepositCheck)
        internal
        view
        returns (VTokenAddress vTokenAddress)
    {
        vTokenAddress = accountStorage.vTokenAddresses[vTokenTruncatedAddress];
        if (vTokenAddress.eq(address(0))) revert UninitializedToken(vTokenTruncatedAddress);
        if (isDepositCheck && !supportedDeposits[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
        if (!isDepositCheck && !supportedVTokens[vTokenAddress]) revert UnsupportedToken(vTokenAddress);
    }

    /// @inheritdoc IClearingHouse
    function createAccount() external notPaused returns (uint256 newAccountId) {
        newAccountId = numAccounts;
        numAccounts = newAccountId + 1; // SSTORE

        Account.Info storage newAccount = accounts[newAccountId];
        newAccount.owner = msg.sender;
        newAccount.tokenPositions.accountNo = newAccountId;

        emit Account.AccountCreated(msg.sender, newAccountId);
    }

    /// @inheritdoc IClearingHouse
    function withdrawProtocolFee(address[] calldata wrapperAddresses) external {
        uint256 totalProtocolFee;
        for (uint256 i = 0; i < wrapperAddresses.length; i++) {
            uint256 wrapperFee = IVPoolWrapper(wrapperAddresses[i]).collectAccruedProtocolFee();
            emit Account.ProtocolFeeWithdrawm(wrapperAddresses[i], wrapperFee);
            totalProtocolFee += wrapperFee;
        }
        IERC20(realBase).transfer(teamMultisig(), totalProtocolFee);
    }

    /// @inheritdoc IClearingHouse
    function addMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external notPaused {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        if (!vTokenAddress.eq(accountStorage.vBaseAddress)) {
            IERC20(vTokenAddress.realToken()).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            IERC20(realBase).safeTransferFrom(msg.sender, address(this), amount);
        }

        account.addMargin(vTokenAddress, amount, accountStorage);

        emit Account.DepositMargin(accountNo, vTokenAddress, amount);
    }

    /// @inheritdoc IClearingHouse
    function removeMargin(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint256 amount
    ) external notPaused {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, true);

        account.removeMargin(vTokenAddress, amount, accountStorage);

        if (!vTokenAddress.eq(accountStorage.vBaseAddress)) {
            IERC20(vTokenAddress.realToken()).safeTransfer(msg.sender, amount);
        } else {
            IERC20(realBase).safeTransfer(msg.sender, amount);
        }

        emit Account.WithdrawMargin(accountNo, vTokenAddress, amount);
    }

    /// @inheritdoc IClearingHouse
    function removeProfit(uint256 accountNo, uint256 amount) external notPaused {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        account.removeProfit(amount, accountStorage);
        IERC20(realBase).transfer(msg.sender, amount);

        emit Account.WithdrawProfit(accountNo, amount);
    }

    /// @inheritdoc IClearingHouse
    function swapToken(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        SwapParams memory swapParams
    ) external notPaused returns (int256 vTokenAmountOut, int256 vBaseAmountOut) {
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        (vTokenAmountOut, vBaseAmountOut) = account.swapToken(vTokenAddress, swapParams, accountStorage);

        uint256 vBaseAmountOutAbs = uint256(vBaseAmountOut.abs());
        if (vBaseAmountOutAbs < accountStorage.minimumOrderNotional) revert LowNotionalValue(vBaseAmountOutAbs);

        if (!swapParams.isPartialAllowed) {
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
        Account.Info storage account = accounts[accountNo];
        if (msg.sender != account.owner) revert AccessDenied(msg.sender);

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);

        checkSlippage(
            vTokenAddress,
            liquidityChangeParams.sqrtPriceCurrent,
            liquidityChangeParams.slippageToleranceBps
        );

        (vTokenAmountOut, vBaseAmountOut) = account.liquidityChange(
            vTokenAddress,
            liquidityChangeParams,
            accountStorage
        );

        uint256 notionalValueAbs = uint256(
            VTokenPositionSet.getNotionalValue(vTokenAddress, vTokenAmountOut, vBaseAmountOut, accountStorage)
        );

        if (notionalValueAbs < accountStorage.minimumOrderNotional) revert LowNotionalValue(notionalValueAbs);
    }

    /// @inheritdoc IClearingHouse
    function removeLimitOrder(
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        int24 tickLower,
        int24 tickUpper
    ) external notPaused returns (uint256 keeperFee) {
        Account.Info storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);
        keeperFee = accountStorage.removeLimitOrderFee + getFixFee();

        account.removeLimitOrder(vTokenAddress, tickLower, tickUpper, keeperFee, accountStorage);

        IERC20(realBase).transfer(msg.sender, keeperFee);
        // emit Account.LiqudityChange(accountNo, tickLower, tickUpper, liquidityDelta, 0, 0, 0);
    }

    /// @inheritdoc IClearingHouse
    function liquidateLiquidityPositions(uint256 accountNo) external notPaused returns (int256 keeperFee) {
        Account.Info storage account = accounts[accountNo];
        int256 insuranceFundFee;
        (keeperFee, insuranceFundFee) = account.liquidateLiquidityPositions(getFixFee(), accountStorage);
        int256 accountFee = keeperFee + insuranceFundFee;

        IERC20(realBase).transfer(msg.sender, uint256(keeperFee));
        transferInsuranceFundFee(insuranceFundFee);

        emit Account.LiquidateRanges(accountNo, msg.sender, accountFee, keeperFee, insuranceFundFee);
    }

    /// @inheritdoc IClearingHouse
    function liquidateTokenPosition(
        uint256 liquidatorAccountNo,
        uint256 accountNo,
        uint32 vTokenTruncatedAddress,
        uint16 liquidationBps
    ) public notPaused returns (Account.BalanceAdjustments memory liquidatorBalanceAdjustments) {
        if (liquidationBps > 10000) revert InvalidTokenLiquidationParameters();
        Account.Info storage account = accounts[accountNo];

        VTokenAddress vTokenAddress = getTokenAddressWithChecks(vTokenTruncatedAddress, false);
        int256 insuranceFundFee;
        (insuranceFundFee, liquidatorBalanceAdjustments) = account.liquidateTokenPosition(
            accounts[liquidatorAccountNo],
            liquidationBps,
            vTokenAddress,
            getFixFee(),
            accountStorage
        );

        transferInsuranceFundFee(insuranceFundFee);
    }

    function transferInsuranceFundFee(int256 insuranceFundFee) internal {
        if (insuranceFundFee > 0) {
            IERC20(realBase).transfer(insuranceFundAddress, uint256(insuranceFundFee));
        } else {
            IInsuranceFund(insuranceFundAddress).claim(uint256(-insuranceFundFee));
        }
    }

    function isVTokenAddressAvailable(uint32 truncated) external view returns (bool) {
        return accountStorage.vTokenAddresses[truncated].eq(address(0));
    }

    function isRealTokenAlreadyInitilized(address realToken) external view returns (bool) {
        return realTokenInitilized[realToken];
    }

    function registerPool(address full, RageTradePool calldata rageTradePool) external onlyRageTradeFactory {
        VTokenAddress vTokenAddress = VTokenAddress.wrap(full);
        uint32 truncated = vTokenAddress.truncate();

        // pool will not be registered twice by the rage trade factory
        assert(accountStorage.vTokenAddresses[truncated].eq(address(0)));

        accountStorage.vTokenAddresses[truncated] = vTokenAddress;
        accountStorage.rtPools[vTokenAddress] = rageTradePool;
    }

    function initRealToken(address realToken) external onlyRageTradeFactory {
        realTokenInitilized[realToken] = true;
    }

    function updateSupportedVTokens(VTokenAddress add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedVTokens[add] = status;
    }

    function updateSupportedDeposits(VTokenAddress add, bool status) external onlyGovernanceOrTeamMultisig {
        supportedDeposits[add] = status;
    }

    function setPaused(bool _pause) external onlyGovernanceOrTeamMultisig {
        paused = _pause;
    }

    // TODO: rename to setGlobalSettings
    function setPlatformParameters(
        LiquidationParams calldata _liquidationParams,
        uint256 _removeLimitOrderFee,
        uint256 _minimumOrderNotional,
        uint256 _minRequiredMargin
    ) external onlyGovernanceOrTeamMultisig {
        accountStorage.liquidationParams = _liquidationParams;
        accountStorage.removeLimitOrderFee = _removeLimitOrderFee;
        accountStorage.minimumOrderNotional = _minimumOrderNotional;
        accountStorage.minRequiredMargin = _minRequiredMargin;
    }

    function updateRageTradePoolSettings(VTokenAddress vTokenAddress, RageTradePoolSettings calldata newSettings)
        public
        onlyGovernanceOrTeamMultisig
    {
        accountStorage.rtPools[vTokenAddress].settings = newSettings;
    }

    modifier onlyRageTradeFactory() {
        if (rageTradeFactory != msg.sender) revert NotRageTradeFactory();
        _;
    }

    modifier notPaused() {
        if (paused) revert Paused();
        _;
    }

    /// @notice Gets fix fee
    /// @dev Allowed to be overriden for specific chain implementations
    /// @return fixFee amount of fixFee in base
    function getFixFee() public view virtual returns (uint256 fixFee) {
        return 0;
    }

    function getTwapSqrtPricesForSetDuration(VTokenAddress vTokenAddress)
        external
        view
        returns (uint256 realPriceX128, uint256 virtualPriceX128)
    {
        realPriceX128 = vTokenAddress.getRealTwapSqrtPriceX96(accountStorage);
        virtualPriceX128 = vTokenAddress.getVirtualTwapPriceX128(accountStorage);
    }

    function rageTradePools(VTokenAddress vTokenAddress) public view returns (RageTradePool memory rageTradePool) {
        return accountStorage.rtPools[vTokenAddress];
    }
}
