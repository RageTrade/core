import { expect } from 'chai';
import { BigNumber } from 'ethers';
import hre from 'hardhat';
import { BisectionTest } from '../../typechain-types';

describe('Bisection', () => {
  let test: BisectionTest;
  before(async () => {
    test = await (await hre.ethers.getContractFactory('BisectionTest')).deploy();
  });

  it('works', async () => {
    expect(await test.findSolution(300, 0, 1000)).to.eq(BigNumber.from(100));
  });

  it('reverts when target is out of bounds', async () => {
    await expect(test.findSolution(300, 101, 1000)).to.be.revertedWith('SolutionOutOfBounds(300, 101, 1000)');
  });
});
