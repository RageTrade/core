import { expect } from 'chai';
import hre from 'hardhat';

import { LiquidityPositionSetTest } from '../../typechain-types';

describe('LiquidityPositionSet Library', () => {
  let test: LiquidityPositionSetTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('LiquidityPositionSetTest');
    test = await factory.deploy();
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
      await expect(test.createEmptyPosition(1, -1)).to.be.revertedWith('IllegalTicks(1, -1)');
    });
  });
});
