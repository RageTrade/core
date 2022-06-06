import { expect } from 'chai';
import hre from 'hardhat';

import { truncate } from '@ragetrade/sdk';

import {
  ClearingHouseTest,
  IOracle,
  IUniswapV3Pool,
  IVPoolWrapper,
  IVToken,
  SettlementTokenMock,
} from '../../typechain-types';
import { ClearingHouseExtsloadTest } from '../../typechain-types/artifacts/contracts/test/ClearingHouseExtsloadTest';
import { vEthFixture } from '../fixtures/vETH';
import { activateMainnetFork } from '../helpers/mainnet-fork';

describe('Clearing House Extsload', () => {
  let clearingHouse: ClearingHouseTest;
  let oracle: IOracle;
  let settlementToken: SettlementTokenMock;
  let vPool: IUniswapV3Pool;
  let vPoolWrapper: IVPoolWrapper;
  let vToken: IVToken;
  let test: ClearingHouseExtsloadTest;

  before(async () => {
    await activateMainnetFork();
    ({ clearingHouse, vToken, vPool, vPoolWrapper, oracle, settlementToken } = await vEthFixture());
    test = await (await hre.ethers.getContractFactory('ClearingHouseExtsloadTest')).deploy();
  });

  describe('protocol', () => {
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

    it('getPoolInfo', async () => {
      const poolExtsload = await test.getPoolInfo(clearingHouse.address, truncate(vToken.address));
      expect(poolExtsload.vToken).to.eq(vToken.address);
      expect(poolExtsload.vPool).to.eq(vPool.address);
      expect(poolExtsload.vPoolWrapper).to.eq(vPoolWrapper.address);
      expect(poolExtsload.settings.oracle).to.eq(oracle.address);

      const poolSload = await clearingHouse.getPoolInfo(truncate(vToken.address));
      expect(poolExtsload).to.deep.eq(poolSload);
    });

    it('getProtocolInfo', async () => {
      const protocolExtsload = await test.getProtocolInfo(clearingHouse.address);
      expect(protocolExtsload.settlementToken).to.eq(settlementToken.address);

      const protocolSload = await clearingHouse.getProtocolInfo();
      expect(protocolExtsload).to.deep.eq(protocolSload);
    });

    it('getCollateralInfo', async () => {
      const collateralExtsload = await test.getCollateralInfo(clearingHouse.address, truncate(settlementToken.address));
      expect(collateralExtsload.token).to.eq(settlementToken.address);

      const collateralSload = await clearingHouse.getCollateralInfo(truncate(settlementToken.address));
      expect(collateralExtsload).to.deep.eq(collateralSload);
    });
  });
});
