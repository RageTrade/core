//SPDX-License-Identifier: UNLICENSED

// pragma solidity ^0.7.6;

// if importing uniswap v3 libraries this might not work
pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '../interfaces/IvToken.sol';

contract vToken is ERC20, IvToken {
    address public immutable override realToken;
    address public immutable perpState;

    constructor(address _realToken, address _perpState) ERC20('vToken', 'vToken') {
        realToken = _realToken;
        perpState = _perpState;
    }
}
