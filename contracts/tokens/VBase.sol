//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IVBase.sol';

contract VBase is IVBase, ERC20, Ownable {
    mapping(address => bool) isAuth;

    constructor() ERC20('vBase', 'vBase') {}

    function mint(address account, uint256 amount) external {
        require(isAuth[msg.sender] == true, 'Not Auth');
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(isAuth[msg.sender] == true, 'Not Auth');
        _burn(account, amount);
    }

    function authorize(address vPoolWrapper) external onlyOwner {
        isAuth[vPoolWrapper] = true;
    }
}
