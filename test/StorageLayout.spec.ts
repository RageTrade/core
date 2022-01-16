import hre from 'hardhat';
import fs from 'fs';
import { getEntryFromStorage, getStorageLayout } from './utils/get-storage-layout';
import { expect } from 'chai';

describe('StorageLayout', () => {
  describe('#ClearingHouse', () => {
    const sourceName = 'contracts/protocol/clearinghouse/ClearingHouse.sol';
    const contractName = 'ClearingHouse';
    it('Account.ProtocolInfo protocol', async () => {
      const { storage } = await getStorageLayout(sourceName, contractName);
      const protocol = getEntryFromStorage(storage, 'protocol');
      expect(protocol.slot).to.eq('100');
    });
  });
});
