//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { console } from 'hardhat/console.sol';

type Uint32L8Set is uint256;

library Uint32L8SetLib {
    using Uint32L8SetLib for Uint32L8Set;

    /**
     * Library methods
     */

    function exists(Uint32L8Set set, uint32 element) internal view returns (bool) {
        return set._indexOf(element) != type(uint8).max;
    }

    function include(Uint32L8Set set, uint32 element) internal view returns (Uint32L8Set) {
        require(element != 0, 'does not support zero elements');
        console.log('hello', element);

        uint accumulatedValue = set.reduce(_includeReducer, uint256(255 << 32) | uint256(element));
        
        // if element is zeroed, then element already exists
        if(accumulatedValue == 255 << 32) {
            console.log('Uint32L8SetLib:include already exists');
            return set;
        }

        uint256 emptyIndex = accumulatedValue >> 32;
        require(emptyIndex != 255, 'limit of 8 vtokens exceeded, pls close positions to create new');

        return Uint32L8Set.wrap(Uint32L8Set.unwrap(set) | (uint256(element) << (emptyIndex * 32)));
    }

    function exclude(Uint32L8Set set, uint32 element) internal view returns (Uint32L8Set) {
        uint8 index = set._indexOf(element);
        console.log('exclude:index', index);
        assembly {
            if lt(index, 8) {
                set := xor(set, shl(element, mul(index, 32)))
            }
        }
        return set;
    }

    // Since this is a set, and order does not matter, index should not be exposed
    function _indexOf(Uint32L8Set set, uint32 element) internal view returns (uint8 index) {
        uint256 accumulatedValue = set.reduce(_indexOfReducer, uint256(255 << 32) | uint256(element));
        index = uint8(accumulatedValue >> 32);
    }

    function _get(Uint32L8Set set, uint8 index) internal pure returns (uint32 element) {
        assembly {
            let intermediate := shr(set, mul(index, 32))
            intermediate := shl(intermediate, 224)
            element := shr(intermediate, 224)
        }
    }

    /**
     *  Core methods
     */

    function reduce(Uint32L8Set set, function(uint256, uint32, uint8) view returns (uint256, bool) fn)
        internal view
        returns (uint256 accumulatedValue)
    {
        return reduce(set, fn, 0);
    }

    function reduce(
        Uint32L8Set set,
        function(uint256, uint32, uint8) view returns (uint256, bool) fn,
        uint256 initialAccumulatedValue
    ) internal view returns (uint256 accumulatedValue) {
        unchecked {
            accumulatedValue = initialAccumulatedValue;
            uint256 unwrapped = Uint32L8Set.unwrap(set);
            uint32 val;
            console.log('reduce-unwrapped', unwrapped);
            for (uint8 i; i < 8; i++) {
                val = uint32(unwrapped >> (32 * i));
                bool stop;
                console.log('reduce-for-inp', accumulatedValue, val, i);
                (accumulatedValue, stop) = fn(accumulatedValue, val, i);
                console.log('reduce-for-res', accumulatedValue, stop);
                if(stop) break;
                unwrapped >>= 8;
            }
        }
    }

    /**
     *  Reducers
     */

    function _existsReducer(uint256 accumulatedValue, uint32 currentElement, uint8) internal pure returns (uint256, bool stop) {
        if (currentElement != 0 && currentElement == accumulatedValue) {
            return (0, true);
        }
        return (accumulatedValue, false);
    }
    
    // uint256 accumulator is split into uint224 emptyIndex and uint32 element
    // element is initialized to current element val. 
    //     If element is changed to null, then it means element is already present in the set
    // emptyIndex is initialized to 255 (where max index is 7).
    //     If emptyIndex is changed to some value (between 0 and 7), then we have to write to it.
    function _includeReducer(uint256 accumulatedValue, uint32 currentElement, uint8 index) internal view returns (uint256, bool) {
        console.log('_includeReducer', accumulatedValue);
        unchecked {
            // if element is found on this iteration, stop the loop
            if(currentElement == uint32(accumulatedValue)) {
                return (uint256(255 << 32), true);
            }
            uint256 emptyIndex = accumulatedValue >> 32;
            if(currentElement == 0 && emptyIndex == 255) {
                emptyIndex = index;
                console.log('_includeReducer2', uint256(emptyIndex << 32) + uint256((accumulatedValue << 224) >> 224));
                return (uint256(emptyIndex << 32)+ uint256((accumulatedValue << 224) >> 224), true);
            }
            return (accumulatedValue, false);
        }
    }

    function _indexOfReducer(uint256 accumulatedValue, uint32 currentElement, uint8 index) internal view returns (uint256, bool) {
        console.log('_indexOfReducer', accumulatedValue);
        uint32 searchElement = uint32((accumulatedValue << 224) >> 224);
        if(searchElement == currentElement) {
            return (index << 32, true);
        }

        console.log('_indexOfReducer2', searchElement, currentElement);
        // return (accumulatedValue, stopValue);
        return (accumulatedValue, false);
    }

}
