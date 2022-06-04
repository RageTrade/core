import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { hexlify, hexZeroPad, keccak256 } from 'ethers/lib/utils';
import hre from 'hardhat';

import { bytes32 } from '@ragetrade/sdk';
import { Bytes32LibTest } from '../../typechain-types/artifacts/contracts/test/Bytes32Test.sol/Bytes32LibTest';

describe('Bytes32Lib', () => {
  let test: Bytes32LibTest;
  before(async () => {
    test = await (await hre.ethers.getContractFactory('Bytes32LibTest')).deploy();
  });

  describe('#slice', () => {
    it('works', async () => {
      expect(await test.slice(bytes32('0xff'), 0, 256)).to.eq(0xff);
      expect(await test.slice(bytes32('0xff'), 0, 248)).to.eq(0);
      expect(await test.slice(bytes32('0xff'), 248, 256)).to.eq(0xff);
      expect(await test.slice(bytes32('0xff0000'), 0, 232)).to.eq(0);
      expect(await test.slice(bytes32('0xff0000'), 232, 256)).to.eq(0xff0000);
      expect(await test.slice(bytes32('0xff0000'), 232, 240)).to.eq(0xff);
    });
  });

  describe('#slice', () => {
    it('keccak256One', async () => {
      const val = hexZeroPad(BigNumber.from(1234).toHexString(), 32);
      const result = await test.keccak256One(val);

      expect(result).to.eq(hexlify(keccak256(val)));
    });
  });

  describe('#pop', () => {
    it('works', async () => {
      const { value, inputUpdated } = await test.pop(bytes32('0xffff'), 8);

      expect(value).to.eq(255);
      expect(inputUpdated).to.eq(bytes32('0xff'));
    });
  });
});
