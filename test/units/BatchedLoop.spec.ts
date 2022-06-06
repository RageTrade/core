import { expect } from 'chai';
import { BigNumber } from 'ethers';
import hre from 'hardhat';

import { BatchedLoopTest, BatchedLoopTest2 } from '../../typechain-types';

const expectLoopToBeCompleted = true;

describe('BatchedLoop', () => {
  describe('Start Index 0', () => {
    let test: BatchedLoopTest;
    beforeEach(async () => {
      test = await (await hre.ethers.getContractFactory('BatchedLoopTest')).deploy();
    });

    it('should work if empty array', async () => {
      await test.setInput([]);

      await test.iterate(1, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([]);
    });

    it('should work if single element in array', async () => {
      await test.setInput([1]);

      await test.iterate(1, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1]);
    });

    it('should do entire iterations when passed 0', async () => {
      await test.setInput([10, 20, 30, 40]);

      await test.iterate(0, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([10, 20, 30, 40]);
    });

    it('should do partial iterations', async () => {
      await test.setInput([1, 2, 3, 4]);

      await test.iterate(2, !expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1, 2]);
      expect(await test.isInProgress()).to.be.true;

      await test.iterate(1, !expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1, 2, 3]);
      expect(await test.isInProgress()).to.be.true;

      await test.iterate(1, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1, 2, 3, 4]);
      expect(await test.isInProgress()).to.be.false;
    });

    it('should work if bad inputs 1', async () => {
      await test.setInput([1, 2, 3, 4]);

      await test.iterate(1000, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1, 2, 3, 4]);
    });

    it('should work if bad inputs 2', async () => {
      await test.setInput([1, 2, 3, 4]);

      await test.iterate(1, !expectLoopToBeCompleted);
      await test.iterate(1000, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq([1, 2, 3, 4]);
    });
  });

  describe('Start Index Non Zero', () => {
    let test: BatchedLoopTest2;
    beforeEach(async () => {
      test = await (await hre.ethers.getContractFactory('BatchedLoopTest2')).deploy();
    });

    it('should work for small batch size', async () => {
      await test.iterate(10, 20, 3, !expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq(sqPlusOne([10, 11, 12]));
    });

    it('should work for huge batch size', async () => {
      await test.iterate(10, 20, 300000, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq(sqPlusOne([10, 11, 12, 13, 14, 15, 16, 17, 18, 19]));
    });

    it('should not do anything if end before start', async () => {
      await test.iterate(20, 10, 300000, expectLoopToBeCompleted);
      expect(num(await test.getOutput())).to.deep.eq(sqPlusOne([]));
    });
  });
});

function num(arr: Array<BigNumber>) {
  return arr.map(val => BigNumber.from(val).toNumber());
}

function sqPlusOne(arr: number[]) {
  return arr.map(val => val * val + 1);
}
