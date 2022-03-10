//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { ERC20Upgradeable } from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';

contract InsuranceFund is IInsuranceFund, Initializable, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    IERC20 public settlementToken;
    IClearingHouse public clearingHouse;

    error Unauthorised();

    /// @notice Initializer for Insurance Fund
    /// @param _settlementToken real base token
    /// @param _clearingHouse address of clearing house (proxy) contract
    /// @param name "Rage Trade iBase"
    /// @param symbol "iBase"
    function __initialize_InsuranceFund(
        IERC20 _settlementToken,
        IClearingHouse _clearingHouse,
        string calldata name,
        string calldata symbol
    ) external initializer {
        settlementToken = _settlementToken;
        clearingHouse = _clearingHouse;
        __ERC20_init(name, symbol);
    }

    function deposit(uint256 amount) external {
        uint256 totalBase = settlementToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 toMint;
        if (totalShares == 0 || totalBase == 0) {
            toMint = amount;
        } else {
            toMint = (amount * totalShares) / totalBase;
        }
        settlementToken.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, toMint);
    }

    function withdraw(uint256 shares) external {
        uint256 totalBase = settlementToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 toWithdraw = (shares * totalBase) / totalShares;
        _burn(msg.sender, shares);
        settlementToken.safeTransfer(msg.sender, toWithdraw);
    }

    function claim(uint256 amount) external {
        if (address(clearingHouse) != msg.sender) revert Unauthorised();
        settlementToken.safeTransfer(msg.sender, amount);
    }
}
