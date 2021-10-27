import { expect } from 'chai';
import hre from 'hardhat';

import { LiquidityPositionTest } from '../typechain';

describe('LiquidityPosition Library', () => {
  let test: LiquidityPositionTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('LiquidityPositionTest');
    test = await factory.deploy();
  });

  describe('#initialize', () => {
    it('first works', async () => {
      await test.initialize(-1, 1);
      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
    });

    it('again reverts', async () => {
      await test.initialize(-1, 1);
      expect(test.initialize(-1, 1)).to.be.revertedWith('AlreadyInitialized()');
    });
  });

  describe('#checkpoints', () => {
    it('zero chkpts', async () => {
      await test.initialize(-1, 1);

      await test.updateCheckpoints();
      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
      expect(lp.liquidity).to.eq(0);
      expect(lp.sumALast).to.eq(0);
      expect(lp.sumBInsideLast).to.eq(0);
      expect(lp.sumFpInsideLast).to.eq(0);
      expect(lp.longsFeeGrowthInsideLast).to.eq(0);
      expect(lp.shortsFeeGrowthInsideLast).to.eq(0);
    });

    it('non-zero chkpts', async () => {
      await test.initialize(-1, 1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumA: 10,
        sumBInside: 20,
        sumFpInside: 30,
        longsFeeGrowthInside: 40,
        shortsFeeGrowthInside: 50,
      });

      await test.updateCheckpoints();

      const lp = await test.lp();
      expect(lp.tickLower).to.eq(-1);
      expect(lp.tickUpper).to.eq(1);
      expect(lp.liquidity).to.eq(0);
      expect(lp.sumALast).to.eq(10);
      expect(lp.sumBInsideLast).to.eq(20);
      expect(lp.sumFpInsideLast).to.eq(30);
      expect(lp.longsFeeGrowthInsideLast).to.eq(40);
      expect(lp.shortsFeeGrowthInsideLast).to.eq(50);
    });
  });

  describe('#liquidityChange', () => {
    it('increase', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);
      expect((await test.lp()).liquidity.toNumber()).to.eq(1, '1*1');
    });

    it('decrease', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);
      await test.liquidityChange(-1);
      expect((await test.lp()).liquidity.toNumber()).to.eq(0);
    });

    it('overflow', async () => {
      await test.initialize(-1, 1);
      expect(test.liquidityChange(-1)).to.be.revertedWith('panic code 0x11');
    });
  });

  describe('#netPosition', () => {
    it('sumB=0', async () => {
      await test.initialize(-1, 1);

      expect(await test.netPosition()).to.eq(0);
    });

    it('sumB=1 and liquidity=0', async () => {
      await test.initialize(-1, 1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: 1,
      });

      expect(await test.netPosition()).to.eq(0, 'should still be 0 as no liquidity');
    });

    it('sumB=1 and liquidity=1', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: 1,
      });

      expect(await test.netPosition()).to.eq(1, '1*1');
    });

    it('sumB=-1 and liquidity=1', async () => {
      await test.initialize(-1, 1);
      await test.liquidityChange(1);

      await setWrapperValueInside({
        tickLower: -1,
        tickUpper: 1,
        sumBInside: -1,
      });

      expect(await test.netPosition()).to.eq(-1, '1*-1');
    });
  });

  async function setWrapperValueInside(val: {
    tickLower: number;
    tickUpper: number;
    sumA?: number;
    sumBInside?: number;
    sumFpInside?: number;
    longsFeeGrowthInside?: number;
    shortsFeeGrowthInside?: number;
  }) {
    const wrapper = await hre.ethers.getContractAt('VPoolWrapperMock', await test.wrapper());
    const existingValues = await wrapper.getValuesInside(val.tickLower, val.tickUpper);
    await wrapper.setValuesInside(
      val.tickLower,
      val.tickUpper,
      val.sumA ?? existingValues.sumA,
      val.sumBInside ?? existingValues.sumBInside,
      val.sumFpInside ?? existingValues.sumFpInside,
      val.longsFeeGrowthInside ?? existingValues.longsFeeGrowthInside,
      val.shortsFeeGrowthInside ?? existingValues.shortsFeeGrowthInside,
    );
  }
});
