import { expect } from 'chai';
import hre from 'hardhat';

import { Uint48L5ArrayTest } from '../../../typechain-types';

describe('Uint48L5Array Library', () => {
  let array: Uint48L5ArrayTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('Uint48L5ArrayTest');
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
      expect(array.include(0)).revertedWith('IllegalElement(0)');
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

    it('limits to 5 includes', async () => {
      for (let i = 1; i <= 5; i++) {
        await array.include(i);
      }
      expect(await array.length()).to.eq(5);
      for (let i = 1; i <= 5; i++) {
        expect(await array.exists(i)).to.be.true;
      }

      expect(array.include(9)).revertedWith('NoSpaceLeftToInsert(9)');
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

    it('zero element', async () => {
      await expect(array.exclude(0)).to.be.revertedWith('U48L5_IllegalElement(0)');
    });

    it('remove element from full array', async () => {
      await array.include(1);
      await array.include(2);
      await array.include(3);
      await array.include(4);
      await array.include(7);

      await array.exclude(2);
    });
  });

  describe('#numberOfNonZeroElements', () => {
    it('works', async () => {
      expect(await array.numberOfNonZeroElements()).to.eq(0);
    });
  });
});
