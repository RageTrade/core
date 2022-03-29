import { expect } from 'chai';
import hre from 'hardhat';

import { Uint48Test } from '../../../typechain-types';

describe('Uint48 Library', () => {
  let test: Uint48Test;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('Uint48Test');
    test = await factory.deploy();
  });

  describe('#concat', () => {
    it('positive.positive#1', async () => {
      const concatenated = await test.assertConcat(1, 1);
      expect(concatenated).to.eq(0x000001_000001);
    });

    it('positive.positive#2', async () => {
      const concatenated = await test.assertConcat(2 ** 23 - 1, 2 ** 23 - 1);
      expect(concatenated).to.eq(0x7fffff_7fffff);
    });

    it('positive.negative#1', async () => {
      const concatenated = await test.assertConcat(1, -1);
      expect(concatenated).to.eq(0x000001_ffffff);
    });

    it('positive.negative#2', async () => {
      const concatenated = await test.assertConcat(2 ** 23 - 1, -1 * 2 ** 23);
      expect(concatenated).to.eq(0x7fffff_800000);
    });

    it('negative.positive#1', async () => {
      const concatenated = await test.assertConcat(-1, 1);
      expect(concatenated).to.eq(0xffffff_000001);
    });

    it('negative.positive#2', async () => {
      const concatenated = await test.assertConcat(-1 * 2 ** 23, 2 ** 23 - 1);
      expect(concatenated).to.eq(0x800000_7fffff);
    });

    it('negative.negative#1', async () => {
      const concatenated = await test.assertConcat(-1, -1);
      expect(concatenated).to.eq(0xffffff_ffffff);
    });

    it('negative.negative#2', async () => {
      const concatenated = await test.assertConcat(-1 * 2 ** 23, -1 * 2 ** 23);
      expect(concatenated).to.eq(0x800000_800000);
    });
  });
});
