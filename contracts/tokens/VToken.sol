//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IVToken } from '../interfaces/IVToken.sol';

contract VToken is ERC20, IVToken {
    address public immutable override oracle;
    address public vPoolWrapper; // TODO change to immutable

    address public immutable realToken;
    uint8 immutable _decimals;

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    constructor(
        string memory vTokenName,
        string memory vTokenSymbol,
        address realToken_,
        address oracle_,
        address vPoolWrapper_
    ) ERC20(vTokenName, vTokenSymbol) {
        realToken = realToken_;
        _decimals = ERC20(realToken_).decimals();
        oracle = oracle_;
        // owner = clearingHouse;
        vPoolWrapper = vPoolWrapper_;
    }

    error Unauthorised();

    function mint(address receiver, uint256 amount) external {
        if (msg.sender != vPoolWrapper) {
            revert Unauthorised();
        }
        _mint(receiver, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // TODO remove this
    function setOwner(address vPoolWrapper_) external {
        vPoolWrapper = vPoolWrapper_;
    }

    // TODO remove this
    function owner() external view returns (address) {
        return vPoolWrapper;
    }
}
