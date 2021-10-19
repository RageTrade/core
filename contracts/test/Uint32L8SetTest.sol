//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { Uint32L8Set, Uint32L8SetLib } from '../libraries/Uint32L8Set.sol';

import { console } from 'hardhat/console.sol';

contract Uint32L8SetTest {
    using Uint32L8SetLib for Uint32L8Set;

    Uint32L8Set set;

    function exists(uint32 element) external view returns (bool) {
        return set.exists(element);
    }

    function include(uint32 element) external {
        set = set.include(element);
        console.log('Uint32L8SetTest:include', Uint32L8Set.unwrap(set));
    }

    function exclude(uint32 element) external {
        set = set.exclude(element);
    }

    function _get(uint8 index) external view returns (uint32) {
        return set._get(index);
    }

    function _indexOf(uint32 element) external view returns (uint8) {
        return set._indexOf(element);
    }

    // Solidity Tests

    function test1() external {
        set = set.include(2000);
        assert(set.exists(2000));
    }

    function test2() external {
        set = set.include(3000);
        assert(set.exists(2000));
        assert(set.exists(3000));
    }
}
