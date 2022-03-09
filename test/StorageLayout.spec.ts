import hre from 'hardhat';
import fs from 'fs';
import { getEntryFromStorage, getStorageLayout, printStorage, StorageEntry } from './utils/get-storage-layout';
import { expect } from 'chai';

interface TestCase {
  label: string;
  slot: number;
  byteOffset?: number;
}

describe('StorageLayout', () => {
  let storage: StorageEntry[];
  describe('#ClearingHouse', () => {
    const sourceName = 'contracts/protocol/clearinghouse/ClearingHouse.sol';
    const contractName = 'ClearingHouse';

    before(async () => {
      ({ storage } = await getStorageLayout(sourceName, contractName));
      // printStorage(storage);
    });

    runTestCases([
      { label: 'protocol', slot: 100 },
      { label: 'numAccounts', slot: 208 },
      { label: 'accounts', slot: 209 },
      { label: 'rageTradeFactoryAddress', slot: 210 },
      { label: 'insuranceFund', slot: 211 },
      { label: 'nativeOracle', slot: 212 },
      { label: '_paused', slot: 364 },
      { label: '_governance', slot: 414 },
      { label: '_teamMultisig', slot: 415 },
    ]);
  });

  describe('#VPoolWrapper', () => {
    const sourceName = 'contracts/protocol/wrapper/VPoolWrapper.sol';
    const contractName = 'VPoolWrapper';

    before(async () => {
      ({ storage } = await getStorageLayout(sourceName, contractName));
      // printStorage(storage);
    });

    runTestCases([
      { label: 'clearingHouse', slot: 0, byteOffset: 2 },
      { label: 'vToken', slot: 1 },
      { label: 'vQuote', slot: 2 },
      { label: 'vPool', slot: 3 },
      { label: 'uniswapFeePips', slot: 3, byteOffset: 20 },
      { label: 'liquidityFeePips', slot: 3, byteOffset: 23 },
      { label: 'protocolFeePips', slot: 3, byteOffset: 26 },
      { label: 'accruedProtocolFee', slot: 4 },
      { label: 'fpGlobal', slot: 5 },
      { label: 'sumFeeGlobalX128', slot: 9 },
      { label: 'ticksExtended', slot: 10 },
    ]);
  });

  function runTestCases(testCases: Array<TestCase>) {
    for (const { label, slot, byteOffset } of testCases) {
      it(`${label} is at ${slot}`, async () => {
        const entry = getEntryFromStorage(storage, label);
        expect(+entry.slot).to.eq(slot);
        expect(+entry.offset).to.eq(byteOffset ?? 0);
      });
    }
  }
});
