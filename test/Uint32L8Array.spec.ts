import { expect } from 'chai';
import hre from 'hardhat';

import { Uint32L8ArrayTest } from '../typechain';

describe('Uint32L8Set Library', () => {
  let array: Uint32L8ArrayTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('Uint32L8ArrayTest');
    array = await factory.deploy();
  });

  describe('#include', () => {
    it('single element', async () => {
      expect(await array.length()).to.eq(0, 'should be 0 initially');

      await array.include(1);

      expect(await array.exists(1)).to.be.true;
      expect(await array.length()).to.eq(1, 'should increase length');
    });

    it('prevents 0', async () => {
      expect(array.include(0)).revertedWith('Uint32L8ArrayLib:include:A');
    });

    it('repeated', async () => {
      await array.include(2);
      const lenPrev = await array.length();
      await array.include(2);
      expect(await array.exists(2)).to.be.true;
      expect(await array.length()).to.eq(lenPrev, 'length should not increase when inserting same element');
    });

    it('multiple', async () => {
      await array.include(1);
      await array.include(2);
      expect(await array.exists(1)).to.be.true;
      expect(await array.exists(2)).to.be.true;
      expect(await array.length()).to.eq(2);
    });

    it('limits to 8 includes', async () => {
      for (let i = 1; i <= 8; i++) {
        await array.include(i);
      }
      expect(await array.length()).to.eq(8);
      for (let i = 1; i <= 8; i++) {
        expect(await array.exists(i)).to.be.true;
      }

      expect(array.include(9)).revertedWith('Uint32L8ArrayLib:include:B');
    });
  });

  describe('#exclude', () => {
    it('single element', async () => {
      await array.include(1);
      await array.exclude(1);
      expect(await array.length()).to.eq(0);
    });

    it('multiple elements', async () => {
      await array.include(1);
      await array.include(2);
      await array.include(3);

      await array.exclude(1);
      expect(await array.length()).to.eq(2);

      await array.exclude(3);
      expect(await array.length()).to.eq(1);

      expect(await array.exists(2)).to.be.true;
    });

    it('non existant element', async () => {
      await array.exclude(10);
      expect(await array.length()).to.eq(0);
    });

    it('middle element', async () => {
      await array.include(1);
      await array.include(2);
      await array.include(3);
      await array.exclude(2);
      expect(await array.length()).to.eq(2);
    });
  });
});
