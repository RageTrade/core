//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '../interfaces/IVToken.sol';

contract VToken is ERC20, IVToken {
    address public immutable override realToken;
    address public immutable override oracle;
    address public immutable owner;

    constructor(
        string memory vTokenName,
        string memory vTokenSymbol,
        address _realToken,
        address _oracle,
        address _perpState
    ) ERC20(vTokenName, vTokenSymbol) {
        realToken = _realToken;
        oracle = _oracle;
        owner = _perpState;
    }

    function mint(address receiver, uint256 amount) external onlyOwner {
        _mint(receiver, amount);
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, 'Not a owner');
        _;
    }
}
