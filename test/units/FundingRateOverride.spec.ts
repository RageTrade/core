import { expect } from 'chai';
import { parseUnits } from 'ethers/lib/utils';
import hre, { ethers } from 'hardhat';

import { smock } from '@defi-wonderland/smock';
import { BigNumber } from '@ethersproject/bignumber';
import { bytes32, toQ128 } from '@ragetrade/sdk';

import { AggregatorV3Interface, FundingRateOverrideTest } from '../../typechain-types';

const PREFIX = '414444524553530000000000'; // "ADDRESS" uint96

describe('FundingRateOverride', () => {
  let test: FundingRateOverrideTest;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('FundingRateOverrideTest')).deploy();
  });

  describe('#constants', () => {
    it('check out prefix', async () => {
      const result = await test.PREFIX();
      expect(result).to.equal('0x' + PREFIX + '0'.repeat(64 - PREFIX.length));
    });

    it('check out null', async () => {
      const result = await test.NULL_VALUE();
      expect(result).to.equal(ethers.constants.MaxInt256.toHexString());
    });
  });

  describe('#packOracleAddress', () => {
    it('works', async () => {
      const result = await test.packOracleAddress('0x1111111111111111111111111111111111111111');
      expect(result).to.equal(`0x1111111111111111111111111111111111111111${PREFIX}`);
    });

    it('reverts for zero address', async () => {
      await expect(test.packOracleAddress('0x0000000000000000000000000000000000000000')).to.be.revertedWith(
        'InvalidFundingRateOracle',
      );
    });
  });

  describe('#packInt256', () => {
    it('works for positive numbers', async () => {
      const result = await test.packInt256(2);
      expect(result).to.equal(bytes32(2));
    });

    it('works for negative numbers', async () => {
      const result = await test.packInt256(-2);
      expect(result).to.equal(ethers.utils.defaultAbiCoder.encode(['int256'], [-2]));
    });

    it('reverts if collides with null', async () => {
      await expect(test.packInt256(ethers.constants.MaxInt256)).to.be.revertedWith(
        `InvalidFundingRateValueX128(${ethers.constants.MaxInt256.toString()})`,
      );
    });

    it('reverts if collides with oracle', async () => {
      const packedAddressBytes32 = await test.packOracleAddress('0x1111111111111111111111111111111111111111');
      await expect(test.packInt256(packedAddressBytes32)).to.be.revertedWith(
        `InvalidFundingRateValueX128(${BigNumber.from(packedAddressBytes32).toString()})`,
      );
    });
  });

  describe('#unpackOracleAddress', () => {
    it('works', async () => {
      const packedAddressBytes32 = await test.packOracleAddress('0x1111111111111111111111111111111111111111');
      const result = await test.unpackOracleAddress(packedAddressBytes32);
      expect(result).to.equal('0x1111111111111111111111111111111111111111');
    });

    it('gives zero address if prefix does not match', async () => {
      const result = await test.unpackOracleAddress(bytes32(12345678));
      expect(result).to.equal('0x0000000000000000000000000000000000000000');
    });
  });

  describe('#unpackInt256', () => {
    it('works for positive numbers', async () => {
      const result = await test.unpackInt256(bytes32(2));
      expect(result).to.equal(2);
    });

    it('works for negative numbers', async () => {
      const result = await test.unpackInt256(bytes32(2));
      expect(result).to.equal(2);
    });
  });

  describe('#setNull', () => {
    it('works', async () => {
      await test.setNull();
      const result = await test.fundingRateOverride();
      expect(result).to.equal(ethers.constants.MaxInt256.toHexString());
    });
  });

  describe('#setOracle', () => {
    it('works', async () => {
      await test.setOracle('0x1111111111111111111111111111111111111111');
      const result = await test.fundingRateOverride();
      expect(result).to.equal(`0x1111111111111111111111111111111111111111${PREFIX}`);
    });

    it('reverts if zero address', async () => {
      await expect(test.setOracle('0x0000000000000000000000000000000000000000')).to.be.revertedWith(
        'InvalidFundingRateOracle',
      );
    });
  });

  describe('#setValueX128', () => {
    it('works', async () => {
      const valueX128 = toQ128(0.5);
      await test.setValueX128(valueX128);
      const result = await test.fundingRateOverride();
      expect(BigNumber.from(result)).to.equal(valueX128);
    });

    it('reverts if collides with null', async () => {
      await expect(test.setValueX128(ethers.constants.MaxInt256)).to.be.revertedWith(
        `InvalidFundingRateValueX128(${ethers.constants.MaxInt256.toString()})`,
      );
    });

    it('reverts if collides with oracle value', async () => {
      const packedAddressBytes32 = await test.packOracleAddress('0x1111111111111111111111111111111111111111');
      await expect(test.setValueX128(packedAddressBytes32)).to.be.revertedWith(
        `InvalidFundingRateValueX128(${BigNumber.from(packedAddressBytes32).toString()})`,
      );
    });
  });

  describe('#getValueX128', () => {
    it('works in NULL mode', async () => {
      await test.setNull();
      const { success, fundingRateOverrideX128 } = await test.getValueX128();
      expect(success).to.be.false;
      expect(fundingRateOverrideX128).to.equal(0);
    });

    it('works in ORACLE mode', async () => {
      const chainlinkContract = await smock.fake<AggregatorV3Interface>('AggregatorV3Interface');
      chainlinkContract.latestRoundData.returns([1, parseUnits('0.5', 8), 1, 1, 1]);
      await test.setOracle(chainlinkContract.address);

      const { success, fundingRateOverrideX128 } = await test.getValueX128();
      expect(success).to.be.true;
      expect(fundingRateOverrideX128).to.eq(toQ128(0.5));
    });

    it('handles failure in ORACLE mode', async () => {
      const chainlinkContract = await smock.fake<AggregatorV3Interface>('AggregatorV3Interface');
      chainlinkContract.latestRoundData.reverts();
      await test.setOracle(chainlinkContract.address);

      const { success, fundingRateOverrideX128 } = await test.getValueX128();
      expect(success).to.be.false;
      expect(fundingRateOverrideX128).to.eq(0);
    });

    it('works in VALUE mode', async () => {
      const valueX128 = toQ128(0.25);
      await test.setValueX128(valueX128);

      const { success, fundingRateOverrideX128 } = await test.getValueX128();
      expect(success).to.be.true;
      expect(fundingRateOverrideX128).to.eq(valueX128);
    });
  });
});
