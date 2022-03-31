import { expect } from 'chai';
import hre from 'hardhat';

import { SignedMathTest } from '../../typechain-types';

describe('SignedMath', () => {
  let test: SignedMathTest;

  before(async () => {
    test = await (await hre.ethers.getContractFactory('SignedMathTest')).deploy();
  });

  describe('#abs', () => {
    it('abs(1) = 1', async () => {
      expect(await test.abs(1)).to.equal(1);
    });

    it('abs(-1) = 1', async () => {
      expect(await test.abs(-1)).to.equal(1);
    });

    it('abs(3) = 3', async () => {
      expect(await test.abs(3)).to.equal(3);
    });

    it('abs(-3) = 3', async () => {
      expect(await test.abs(-3)).to.equal(3);
    });

    it('abs(0) = 0', async () => {
      expect(await test.abs(0)).to.equal(0);
    });
  });

  describe('#absUint', () => {
    it('absUint(1) = 1', async () => {
      expect(await test.absUint(1)).to.equal(1);
    });

    it('absUint(-1) = 1', async () => {
      expect(await test.absUint(-1)).to.equal(1);
    });

    it('absUint(3) = 3', async () => {
      expect(await test.absUint(3)).to.equal(3);
    });

    it('absUint(-3) = 3', async () => {
      expect(await test.absUint(-3)).to.equal(3);
    });

    it('absUint(0) = 0', async () => {
      expect(await test.absUint(0)).to.equal(0);
    });
  });

  describe('#sign', () => {
    it('sign(1) = 1', async () => {
      expect(await test.sign(1)).to.equal(1);
    });

    it('sign(-1) = -1', async () => {
      expect(await test.sign(-1)).to.equal(-1);
    });

    it('sign(3) = 1', async () => {
      expect(await test.sign(3)).to.equal(1);
    });

    it('sign(-3) = -1', async () => {
      expect(await test.sign(-3)).to.equal(-1);
    });

    it('sign(0) = 1', async () => {
      expect(await test.sign(0)).to.equal(1);
    });
  });

  describe('#extractSign', () => {
    it('extractSign(1) = [1,true]', async () => {
      const [val, sign] = await test['extractSign(int256)'](1);
      expect(val).to.equal(1);
      expect(sign).to.equal(true);
    });

    it('extractSign(-1) = [1,false]', async () => {
      const [val, sign] = await test['extractSign(int256)'](-1);
      expect(val).to.equal(1);
      expect(sign).to.equal(false);
    });

    it('extractSign(3) = [3,true]', async () => {
      const [val, sign] = await test['extractSign(int256)'](3);
      expect(val).to.equal(3);
      expect(sign).to.equal(true);
    });

    it('extractSign(-3) = [3,false]', async () => {
      const [val, sign] = await test['extractSign(int256)'](-3);
      expect(val).to.equal(3);
      expect(sign).to.equal(false);
    });
  });
});
