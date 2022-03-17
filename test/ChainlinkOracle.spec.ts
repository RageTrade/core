import { FakeContract, smock } from '@defi-wonderland/smock';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { ChainlinkOracle, MockAggregatorV3 } from '../typechain-types';
import { parseTokenAmount } from './utils/stealFunds';

describe('ChainlinkPriceFeed Spec', () => {
  let chainlinkOracle: ChainlinkOracle;
  let aggregator: FakeContract<MockAggregatorV3>;
  let currentTime: number;
  let roundData: any[];

  async function resetAggregator() {
    aggregator.getRoundData.returns((input: any) => {
      return roundData[input];
    });

    aggregator.latestRoundData.returns(roundData[roundData.length - 1]);
  }

  before(async () => {
    aggregator = await smock.fake('MockAggregatorV3');
    aggregator.decimals.returns(8);

    chainlinkOracle = await (await ethers.getContractFactory('ChainlinkOracle')).deploy(aggregator.address, 18, 6);
  });

  describe('Error Handling', () => {
    beforeEach(async () => {
      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
      currentTime = latestTimestamp;
      roundData = [];

      // [roundId, answer, startedAt, updatedAt, answeredInRound]
      currentTime += 0;
      roundData.push([0, parseTokenAmount('-1000', 8), currentTime, currentTime, 0]);

      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);

      currentTime += 15;
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime]);
      await ethers.provider.send('evm_mine', []);
    });

    it('Not Enough History', async () => {
      expect(chainlinkOracle.getTwapPriceX128(45)).to.be.revertedWith('NotEnoughHistory()');
    });
  });

  describe('Chainlink failure handling', () => {
    beforeEach(async () => {
      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
      currentTime = latestTimestamp;
      roundData = [];

      // [roundId, answer, startedAt, updatedAt, answeredInRound]
      currentTime += 0;
      roundData.push([0, parseTokenAmount('3000', 8), currentTime, currentTime, 0]);

      currentTime += 60;
      roundData.push([1, parseTokenAmount('3050', 8), currentTime, currentTime, 1]);

      currentTime += 60;
      roundData.push([2, parseTokenAmount('3100', 8), currentTime, currentTime, 2]);

      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);

      currentTime += 60;
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime]);
      await ethers.provider.send('evm_mine', []);
    });
    it('Aggregator getRoundData reverts', async () => {
      aggregator.getRoundData.revertsAtCall(0, 'Error');
      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3100', 6).sub(1));
    });
    it('Aggregator getRoundData reverts after 1 call', async () => {
      //Returns data on first roundData call and reverts on second call
      aggregator.getRoundData.revertsAtCall(2, 'Error');
      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3075', 6).sub(1));
    });
  });

  describe('Different Timestamps for each round', () => {
    beforeEach(async () => {
      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
      currentTime = latestTimestamp;
      roundData = [];

      // [roundId, answer, startedAt, updatedAt, answeredInRound]
      currentTime += 0;
      roundData.push([0, parseTokenAmount('3000', 8), currentTime, currentTime, 0]);

      currentTime += 60;
      roundData.push([1, parseTokenAmount('3050', 8), currentTime, currentTime, 1]);

      currentTime += 60;
      roundData.push([2, parseTokenAmount('3100', 8), currentTime, currentTime, 2]);

      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);

      currentTime += 60;
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime]);
      await ethers.provider.send('evm_mine', []);
    });

    it('Twap Duration = History', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3050', 6).sub(1));
    });

    it('Twap Duration > History', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(200);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3050', 6).sub(1));
    });

    it('Twap Duration < History', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(150);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3060', 6).sub(1));
    });

    it('Twap Duration = History', async () => {
      roundData.push([4, parseTokenAmount('3200', 8), currentTime + 60, currentTime + 60, 4]);
      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime + 100]);
      await ethers.provider.send('evm_mine', []);
      const price = await chainlinkOracle.getTwapPriceX128(200);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3110', 6).sub(1));
    });

    it('(Now - Twap Duration) > Last Update TS', async () => {
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime + 100]);
      await ethers.provider.send('evm_mine', []);

      const price = await chainlinkOracle.getTwapPriceX128(60);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3100', 6).sub(1));
    });

    it('Latest Price is Negative', async () => {
      roundData.push([3, parseTokenAmount('-1000', 8), 360, 360, 3]);
      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);
      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3050', 6).sub(1));
    });

    it('Middle Price is Negative', async () => {
      roundData.push([3, parseTokenAmount('-1000', 8), currentTime + 60, currentTime + 60, 3]);
      roundData.push([4, parseTokenAmount('3200', 8), currentTime + 120, currentTime + 120, 4]);
      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime + 180]);
      await ethers.provider.send('evm_mine', []);

      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq('3133333333');
    });

    it('Twap Duration = 0', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(0);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3100', 6).sub(1));
    });
  });

  describe('Same Timestamps for multiple rounds', () => {
    beforeEach(async () => {
      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp;
      currentTime = latestTimestamp;
      roundData = [];

      // [roundId, answer, startedAt, updatedAt, answeredInRound]
      roundData.push([0, parseTokenAmount('3000', 8), currentTime, currentTime, 0]);
      roundData.push([1, parseTokenAmount('3050', 8), currentTime, currentTime, 1]);
      roundData.push([2, parseTokenAmount('3100', 8), currentTime, currentTime, 2]);

      aggregator.getRoundData.returns((input: any) => {
        return roundData[input];
      });

      aggregator.latestRoundData.returns(roundData[roundData.length - 1]);

      currentTime += 60;
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentTime]);
      await ethers.provider.send('evm_mine', []);
    });

    it('Twap Duration = History', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(180);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3100', 6).sub(1));
    });

    it('Twap Duration > History', async () => {
      const price = await chainlinkOracle.getTwapPriceX128(200);
      expect(price.mul(10n ** 18n).div(1n << 128n)).to.eq(parseTokenAmount('3100', 6).sub(1));
    });
  });
});
