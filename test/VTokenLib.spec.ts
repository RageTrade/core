import { expect } from 'chai';
import hre from 'hardhat';
import { constants } from './utils/dummyConstants';

import { VTokenLibTest } from '../typechain-types';
const vTokenAdddres = '0xbb72710011FE06C29B9D5817952482b521812E09';
const vPoolAddress = '0x198A9653be67B78e4B59c2BabFfa9b4Db4dAcB81';
const vPoolWrapper = '0xcd5d7401398772aade751445133c5bbf972321a8';

describe('VTokenLib Library', () => {
  let vTokenLib: VTokenLibTest;
  before(async () => {
    const factory = await hre.ethers.getContractFactory('VTokenLibTest');
    vTokenLib = (await factory.deploy()) as unknown as VTokenLibTest;
  });

  describe('Functions', () => {
    // vPool address is not computed now
    it.skip('vPool', async () => {
      const result = await vTokenLib.vPool(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolAddress.toLowerCase());
    });

    // vPoolWrapper address is not computed now
    it.skip('vPoolWrapper', async () => {
      const result = await vTokenLib.vPoolWrapper(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolWrapper.toLowerCase());
    });
  });
});
