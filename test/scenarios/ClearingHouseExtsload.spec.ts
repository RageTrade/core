import hre from 'hardhat';
import { ClearingHouse, IUniswapV3Pool, IVToken } from '../../typechain-types';
import { vEthFixture } from '../fixtures/vETH';
import { truncate } from '../helpers/vToken';
import { ClearingHouseExtsloadTest } from '../../typechain-types/artifacts/contracts/test/ClearingHouseExtsloadTest';
import { expect } from 'chai';
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
      const result = await test.pools_vPool(clearingHouse.address, truncate(vToken.address));
      expect(result).to.eq(vPool.address);
    });

    it('settings', async () => {
      const result = await test.pools_settings(clearingHouse.address, truncate(vToken.address));
      const poolInfo = await clearingHouse.getPoolInfo(truncate(vToken.address));

      expect(result).to.deep.eq(poolInfo.settings);
    });

    it('vPool and twapDuration', async () => {
      await test.check_pools_vPool_and_settings_twapDuration(clearingHouse.address, truncate(vToken.address));
      const result = await test.pools_vPool_and_settings_twapDuration(clearingHouse.address, truncate(vToken.address));
      expect(result.vPool).to.eq(vPool.address);
      const poolInfo = await clearingHouse.getPoolInfo(truncate(vToken.address));
      expect(result.twapDuration).to.eq(poolInfo.settings.twapDuration);
    });
  });
});
