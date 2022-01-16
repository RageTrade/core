import hre from 'hardhat';
import fs from 'fs';
import { getEntryFromStorage, getStorageLayout } from './utils/get-storage-layout';
import { expect } from 'chai';

describe('StorageLayout', () => {
  describe('#ClearingHouse', () => {
    const sourceName = 'contracts/protocol/clearinghouse/ClearingHouse.sol';
    const contractName = 'ClearingHouse';
    it('accountStorage', async () => {
      const { storage } = await getStorageLayout(sourceName, contractName);
      const protocol = getEntryFromStorage(storage, 'accountStorage');
      expect(protocol.slot).to.eq('100');
    });
  });
});
