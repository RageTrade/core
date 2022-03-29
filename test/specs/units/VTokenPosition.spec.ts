import { expect } from 'chai';
import hre from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionTest } from '../../../typechain-types';

describe('VTokenPosition Library', () => {
  let VTokenPosition: VTokenPositionTest;
  const priceX96 = BigNumber.from('242445728302062693925');
  const balance = BigNumber.from('10').pow(18);

  before(async () => {
    const factory = await hre.ethers.getContractFactory('VTokenPositionTest');
    VTokenPosition = (await factory.deploy()) as unknown as VTokenPositionTest;
    await VTokenPosition.init(balance, -10, 10n * (1n << 128n));
  });

  describe('Functions', () => {
    it('unrealizedFundingPayment', async () => {
      const result = await VTokenPosition.unrealizedFundingPayment();
      expect(result).to.eq(100);
    });
    it('marketValue', async () => {
      const priceX128 = priceX96.mul(priceX96).div(1n << 64n);
      const result = await VTokenPosition.marketValue(priceX128);
      expect(result).to.eq(
        balance
          .mul(priceX128)
          .div(1n << 128n)
          .add(100),
      );
    });
    it('riskSide', async () => {
      const result = await VTokenPosition.riskSide();
      expect(result).to.eq(0);
    });
  });
});
