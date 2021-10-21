//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

type Uint48L8Set is uint256;

library Uint48L8SetLib {
    using Uint48L8SetLib for Uint48L8Set;

    /**
     * Library methods
     */

    function exists(Uint48L8Set set, uint48 element) internal view returns (bool) {
        return set._indexOf(element) != type(uint8).max;
    }

    function include(Uint48L8Set set, uint48 element) internal view returns (Uint48L8Set) {
        require(element != 0, 'does not support zero elements');
        uint accumulatedValue = set.reduce(_existsReducer, (255 << 48) | element);
        
        // stop if element already exists
        if(uint48(accumulatedValue) == 0) {
            return set;
        }

        uint256 emptyIndex = accumulatedValue >> 48;
        require(emptyIndex != 255, 'limit of 8 vtokens exceeded, pls close positions to create new');

        return Uint48L8Set.wrap(Uint48L8Set.unwrap(set) | uint256(element) << (emptyIndex * 48));
    }

    function exclude(Uint48L8Set set, uint48 element) internal view {
        uint8 index = set._indexOf(element);
        assembly {
            if lt(index, 8) {
                set := xor(set, shl(element, mul(index, 48)))
            }
        }
    }

    // Since this is a set, and order does not matter, index should not be exposed
    function _indexOf(Uint48L8Set set, uint48 element) internal view returns (uint8 index) {
        uint256 accumulatedValue = set.reduce(_indexOfReducer, (255 << 48) | element);
        index = uint8(accumulatedValue >> 48);
    }

    function _get(Uint48L8Set set, uint8 index) internal pure returns (uint48 element) {
        assembly {
            let intermediate := shr(set, mul(index, 48))
            intermediate := shl(intermediate, 208) // 256-48
            element := shr(intermediate, 208)
        }
    }

    /**
     *  Core methods
     */

    function reduce(Uint48L8Set set, function(uint256, uint48, uint8) view returns (uint256, bool) fn)
        internal view
        returns (uint256 accumulatedValue)
    {
        return reduce(set, fn, 0);
    }

    function reduce(
        Uint48L8Set set,
        function(uint256, uint48, uint8) view returns (uint256, bool) fn,
        uint256 initialAccumulatedValue
    ) internal view returns (uint256 accumulatedValue) {
        unchecked {
            accumulatedValue = initialAccumulatedValue;
            uint256 unwrapped = Uint48L8Set.unwrap(set);
            uint48 val;
            for (uint8 i; i < 8; i++) {
                val = uint48(unwrapped);
                bool stop;
                (accumulatedValue, stop) = fn(accumulatedValue, val, i);
                if(stop) break;
                unwrapped >>= 8;
            }
        }
    }

    /**
     *  Reducers
     */

    function _existsReducer(uint256 accumulatedValue, uint48 currentElement, uint8) internal pure returns (uint256, bool stop) {
        if (currentElement != 0 && currentElement == accumulatedValue) {
            return (0, true);
        }
        return (accumulatedValue, false);
    }
    
    // uint256 accumulator is split into uint208 emptyIndex and uint48 element
    // element is initialized to current element val. 
    //     If element is changed to null, then it means element is already present in the set
    // emptyIndex is initialized to 255 (where max index is 7).
    //     If emptyIndex is changed to some value (between 0 and 7), then we have to write to it.
    function _includeReducer(uint256 accumulatedValue, uint48 currentElement, uint8 index) internal pure returns (uint256, bool) {
        unchecked {
            // if element is found on this iteration, stop the loop
            if(currentElement == uint48(accumulatedValue)) {
                return (0, true);
            }
            uint256 emptyIndex = accumulatedValue >> 48;
            if(currentElement == 0 && emptyIndex == 255) {
                emptyIndex = index;
            }
            return (emptyIndex << 48 + uint48(accumulatedValue), false);
        }
    }

    function _indexOfReducer(uint256 accumulatedValue, uint48 currentElement, uint8 index) internal pure returns (uint256, bool) {
        uint256 searchElement;
        assembly {
            searchElement := shl(accumulatedValue, 208)
            searchElement := shr(searchElement, 208)

            if eq(searchElement, currentElement) {
                return (shr(index, 48), true)
            }

            return (accumulatedValue, false)
        }
    }

}
