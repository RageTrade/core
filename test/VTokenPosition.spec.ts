import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionTest, ClearingHouse } from '../typechain-types';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

describe('VTokenPosition Library', () => {
  let VTokenPosition: VTokenPositionTest;
  const vTokenAddress = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  const Q96: BigNumber = BigNumber.from('0x1000000000000000000000000');
  const priceX96 = BigNumber.from('242445728302062693925');
  const balance = BigNumber.from('10').pow(18);

  before(async () => {
    const factory = await hre.ethers.getContractFactory('VTokenPositionTest');
    VTokenPosition = (await factory.deploy()) as unknown as VTokenPositionTest;
    await VTokenPosition.init(balance, -10, 10);
  });

  describe('Functions', () => {
    it('unrealizedFundingPayment', async () => {
      const result = await VTokenPosition.unrealizedFundingPayment();
      expect(result).to.eq(-100);
    });
    it('marketValue', async () => {
      const result = await VTokenPosition.marketValue(priceX96);
      expect(result).to.eq(balance.mul(priceX96).div(Q96).add(100));
    });
    it('riskSide', async () => {
      const result = await VTokenPosition.riskSide();
      expect(result).to.eq(0);
    });
  });
});
