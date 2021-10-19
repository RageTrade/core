import { expect } from 'chai';
import hre from 'hardhat';

import { Uint32L8SetTest } from '../typechain';

describe('Uint32L8Set Library', () => {
  let set: Uint32L8SetTest;

  before(async () => {
    const factory = await hre.ethers.getContractFactory('Uint32L8SetTest');
    set = await factory.deploy();
  });

  describe('#include', () => {
    it('single element', async () => {
      await set.include(2000);
      expect(await set.exists(2000)).to.eq(true);
    });
  });

  describe('#excude', () => {
    before(async () => {
      console.log(3);

      // insert some elements
      await set.include(2000);
      await set.include(3000);
      await set.include(4000);
      console.log(4);
    });

    it('2000', async () => {
      console.log(1);

      expect(await set.exists(2000)).to.eq(true);
      console.log(1);
      await set.exclude(2000);
      expect(await set.exists(2000)).to.eq(false);
    });
  });
});
