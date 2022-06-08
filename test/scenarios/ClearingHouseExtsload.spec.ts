import { expect } from 'chai';
import hre from 'hardhat';

import { parseUsdc, truncate } from '@ragetrade/sdk';

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
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

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

    // hre.tracer.enabled = true;
    // hre.tracer.sloads = true;
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

  describe('account', () => {
    let accountId: number;
    let signer: SignerWithAddress;
    before(async () => {
      [signer] = await hre.ethers.getSigners();
      await settlementToken.mint(signer.address, parseUsdc('1000000'));
      accountId = (await clearingHouse.callStatic.createAccount()).toNumber();
      await clearingHouse.createAccount();
      await clearingHouse.updateMargin(accountId, truncate(settlementToken.address), parseUsdc('1000000'));
      const { tick, sqrtPriceX96 } = await vPool.slot0();
      const tickFloor = Math.floor(tick / 1000) * 1000;

      await clearingHouse.updateRangeOrder(accountId, truncate(vToken.address), {
        tickLower: tickFloor - 10000,
        tickUpper: tickFloor + 10000,
        liquidityDelta: 100000000000000,
        sqrtPriceCurrent: sqrtPriceX96,
        slippageToleranceBps: 10000,
        closeTokenPosition: false,
        limitOrderType: 0,
        settleProfit: false,
      });

      await clearingHouse.swapToken(accountId, truncate(vToken.address), {
        amount: parseUsdc('1'),
        sqrtPriceLimit: sqrtPriceX96.mul(2),
        isNotional: true,
        isPartialAllowed: true,
        settleProfit: false,
      });
    });

    it('getAccountInfo', async () => {
      const accountExtsload = await test.getAccountInfo(clearingHouse.address, accountId);
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(accountExtsload.owner).to.eq(accountSload.owner);
      expect(accountExtsload.vQuoteBalance).to.deep.eq(accountSload.vQuoteBalance);

      expect(accountExtsload.activeCollateralIds.length).to.eq(accountSload.collateralDeposits.length);
      accountExtsload.activeCollateralIds.forEach((_, i) => {
        expect(accountExtsload.activeCollateralIds[i]).to.eq(
          Number(truncate(accountSload.collateralDeposits[i].collateral)),
        );
      });

      expect(accountExtsload.activePoolIds.length).to.eq(accountSload.tokenPositions.length);
      accountExtsload.activePoolIds.forEach((_, i) => {
        expect(accountExtsload.activePoolIds[i]).to.eq(accountSload.tokenPositions[i].poolId);
      });
    });

    it('getAccountInfo', async () => {
      const accountExtsload = await test.getAccountInfo(clearingHouse.address, accountId);
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(accountExtsload.owner).to.eq(accountSload.owner);
      expect(accountExtsload.vQuoteBalance).to.deep.eq(accountSload.vQuoteBalance);

      expect(accountExtsload.activeCollateralIds.length).to.eq(accountSload.collateralDeposits.length);
      accountExtsload.activeCollateralIds.forEach((_, i) => {
        expect(accountExtsload.activeCollateralIds[i]).to.eq(
          Number(truncate(accountSload.collateralDeposits[i].collateral)),
        );
      });

      expect(accountExtsload.activePoolIds.length).to.eq(accountSload.tokenPositions.length);
      accountExtsload.activePoolIds.forEach((_, i) => {
        expect(accountExtsload.activePoolIds[i]).to.eq(accountSload.tokenPositions[i].poolId);
      });

      // tracer.enabled = false;
    });

    it('getAccountCollateralInfo', async () => {
      const collateralExtsload = await test.getAccountCollateralInfo(
        clearingHouse.address,
        accountId,
        truncate(settlementToken.address),
      );
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(collateralExtsload.collateral).to.eq(accountSload.collateralDeposits[0].collateral);
      expect(collateralExtsload.balance).to.deep.eq(accountSload.collateralDeposits[0].balance);
    });

    it('getAccountCollateralBalance', async () => {
      const balanceExtsload = await test.getAccountCollateralBalance(
        clearingHouse.address,
        accountId,
        truncate(settlementToken.address),
      );
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(balanceExtsload).to.deep.eq(accountSload.collateralDeposits[0].balance);
    });

    it('getAccountTokenPositionInfo', async () => {
      const tokenPositionExtsload = await test.getAccountTokenPositionInfo(
        clearingHouse.address,
        accountId,
        truncate(vToken.address),
      );
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(tokenPositionExtsload.balance).to.deep.eq(accountSload.tokenPositions[0].balance);
      expect(tokenPositionExtsload.netTraderPosition).to.deep.eq(accountSload.tokenPositions[0].netTraderPosition);
      expect(tokenPositionExtsload.sumALastX128).to.deep.eq(accountSload.tokenPositions[0].sumALastX128);
    });

    it('getAccountPositionInfo', async () => {
      const tokenPositionExtsload = await test.getAccountPositionInfo(
        clearingHouse.address,
        accountId,
        truncate(vToken.address),
      );
      const accountSload = await clearingHouse.getAccountInfo(accountId);

      expect(tokenPositionExtsload.balance).to.deep.eq(accountSload.tokenPositions[0].balance);
      expect(tokenPositionExtsload.netTraderPosition).to.deep.eq(accountSload.tokenPositions[0].netTraderPosition);
      expect(tokenPositionExtsload.sumALastX128).to.deep.eq(accountSload.tokenPositions[0].sumALastX128);
    });
  });
});
