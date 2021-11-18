//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IInsuranceFund.sol';
import 'hardhat/console.sol';

contract InsuranceFund is IInsuranceFund, ERC20 {
    using SafeERC20 for IERC20;
    IERC20 public base;
    address public owner;

    constructor(IERC20 _base, address _clearingHouse) ERC20('iBase', 'iBase') {
        base = _base;
        owner = _clearingHouse;
    }

    function deposit(uint256 amount) external {
        uint256 totalBase = base.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 toMint;
        console.log('Deposit', totalBase, totalShares);
        if (totalShares == 0 || totalBase == 0) {
            toMint = amount;
        } else {
            toMint = (amount * totalShares) / totalBase;
        }
        _mint(msg.sender, toMint);
        base.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 shares) external {
        uint256 totalBase = base.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        console.log('Withdraw', totalBase, totalShares);
        uint256 toWithdraw = (shares * totalBase) / totalShares;
        _burn(msg.sender, shares);
        base.safeTransfer(msg.sender, toWithdraw);
    }

    function claim(uint256 amount) external {
        require(owner == msg.sender, 'Not welcome');
        base.safeTransfer(msg.sender, amount);
    }
}
