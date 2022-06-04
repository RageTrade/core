import { expect } from 'chai';
import hre from 'hardhat';

import { truncate } from '@ragetrade/sdk';

import { ClearingHouse, IUniswapV3Pool, IVToken } from '../../typechain-types';
import { ClearingHouseExtsloadTest } from '../../typechain-types/artifacts/contracts/test/ClearingHouseExtsloadTest';
import { vEthFixture } from '../fixtures/vETH';
import { activateMainnetFork } from '../helpers/mainnet-fork';

describe('Clearing House Extsload', () => {
  let clearingHouse: ClearingHouse;
  let vPool: IUniswapV3Pool;
  let vToken: IVToken;
  let test: ClearingHouseExtsloadTest;

  before(async () => {
    await activateMainnetFork();
    ({ clearingHouse, vToken, vPool } = await vEthFixture());
    test = await (await hre.ethers.getContractFactory('ClearingHouseExtsloadTest')).deploy();
  });

  describe('pools', () => {
    it('vPool', async () => {
      const result = await test.getVPool(clearingHouse.address, truncate(vToken.address));
      expect(result).to.eq(vPool.address);
    });

    it('settings', async () => {
      const result = await test.getPoolSettings(clearingHouse.address, truncate(vToken.address));
      const poolInfo = await clearingHouse.getPoolInfo(truncate(vToken.address));

      expect(result).to.deep.eq(poolInfo.settings);
    });

    it('vPool and twapDuration', async () => {
      await test.checkVPoolAndTwapDuration(clearingHouse.address, truncate(vToken.address));
      const result = await test.getVPoolAndTwapDuration(clearingHouse.address, truncate(vToken.address));
      expect(result.vPool).to.eq(vPool.address);
      const poolInfo = await clearingHouse.getPoolInfo(truncate(vToken.address));
      expect(result.twapDuration).to.eq(poolInfo.settings.twapDuration);
    });

    it('isPoolIdAvailable', async () => {
      // an already created pool should not be available
      const result1 = await test.isPoolIdAvailable(clearingHouse.address, truncate(vToken.address));
      expect(result1).to.be.false;

      // an created pool should not be available
      const result2 = await test.isPoolIdAvailable(clearingHouse.address, 0x12345678);
      expect(result2).to.be.true;
    });
  });
});
