import { expect } from 'chai';
import hre from 'hardhat';

import { LiquidityPositionTest } from '../typechain';

describe('Liquidity Position Library', () => {
  let test: LiquidityPositionTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('LiquidityPositionTest');
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

  describe('#create', () => {
    it('empty', async () => {
      expect(await test.isPositionActive(-1, 1)).to.be.false;

      await test.createEmptyPosition(-1, 1);
      const position = await test.callStatic.createEmptyPosition(-1, 1);

      expect(await test.isPositionActive(-1, 1)).to.be.true;
      expect(position.tickLower).to.eq(-1);
      expect(position.tickUpper).to.eq(1);
      expect(position.liquidity).to.eq(0);
    });

    it('invalid', async () => {
      expect(test.createEmptyPosition(1, -1)).to.be.revertedWith('InvalidTicks(1, -1)');
    });
  });
});
