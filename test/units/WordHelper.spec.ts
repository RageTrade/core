import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { getAddress, hexlify, hexZeroPad, keccak256 } from 'ethers/lib/utils';
import hre from 'hardhat';

import { bytes32 } from '@ragetrade/sdk';
import { WordHelperTest } from '../../typechain-types/artifacts/contracts/test/WordHelperTest';

describe('WordHelper', () => {
  let test: WordHelperTest;
  before(async () => {
    test = await (await hre.ethers.getContractFactory('WordHelperTest')).deploy();
  });

  describe('#slice', () => {
    it('works', async () => {
      expect(await test.slice(bytes32(0xff), 0, 256)).to.eq(bytes32(0xff));
      expect(await test.slice(bytes32(0xff), 0, 248)).to.eq(bytes32(0));
      expect(await test.slice(bytes32(0xff), 248, 256)).to.eq(bytes32(0xff));
      expect(await test.slice(bytes32(0xff0000), 0, 232)).to.eq(bytes32(0));
      expect(await test.slice(bytes32(0xff0000), 232, 256)).to.eq(bytes32(0xff0000));
      expect(await test.slice(bytes32(0xff0000), 232, 240)).to.eq(bytes32(0xff));
    });
  });

  describe('#keccak256', () => {
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

    it('works 2', async () => {
      const result1 = await test.pop(bytes32('0x0102030405060708091011121314151617181920212223242526272829303132'), 16);

      expect(result1.value).to.eq(0x3132);
      expect(result1.inputUpdated).to.eq(bytes32('0x010203040506070809101112131415161718192021222324252627282930'));

      const result2 = await test.pop(result1.inputUpdated, 16);

      expect(result2.value).to.eq(0x2930);
      expect(result2.inputUpdated).to.eq(bytes32('0x01020304050607080910111213141516171819202122232425262728'));
    });

    it('popAddress', async () => {
      const result = await test.popAddress('0x000000000000000000000000a0ee1784799cc91a1344b3b8c6fa5cc0becf0f23');

      expect(result.value).to.eq(getAddress('0xa0ee1784799cc91a1344b3b8c6fa5cc0becf0f23'));
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popAddress full', async () => {
      const result = await test.popAddress('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value).to.eq(getAddress('0x1314151617181920212223242526272829303132'));
      expect(result.inputUpdated).to.eq(bytes32('0x010203040506070809101112'));
    });

    it('popUint8', async () => {
      const result = await test.popUint8(bytes32(0x12));

      expect(result.value).to.eq(0x12);
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popUint8 full', async () => {
      const result = await test.popUint8('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value).to.eq(0x32);
      expect(result.inputUpdated).to.eq(bytes32('0x01020304050607080910111213141516171819202122232425262728293031'));
    });

    it('popUint16', async () => {
      const result = await test.popUint16(bytes32(0x1234));

      expect(result.value).to.eq(0x1234);
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popUint16 full', async () => {
      const result = await test.popUint16('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value).to.eq(0x3132);
      expect(result.inputUpdated).to.eq(bytes32('0x010203040506070809101112131415161718192021222324252627282930'));
    });

    it('popUint32', async () => {
      const result = await test.popUint32(bytes32(0x12345678));

      expect(result.value).to.eq(0x12345678);
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popUint32 full', async () => {
      const result = await test.popUint32('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value).to.eq(0x29303132);
      expect(result.inputUpdated).to.eq(bytes32('0x01020304050607080910111213141516171819202122232425262728'));
    });

    it('popUint64', async () => {
      const result = await test.popUint64(bytes32('0x1234567812345678'));

      expect(result.value.toHexString()).to.eq('0x1234567812345678');
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popUint64 full', async () => {
      const result = await test.popUint64('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value.toHexString()).to.eq('0x2526272829303132');
      expect(result.inputUpdated).to.eq(bytes32('0x010203040506070809101112131415161718192021222324'));
    });

    it('popUint128', async () => {
      const result = await test.popUint128(bytes32('0x12345678123456781234567812345678'));

      expect(result.value.toHexString()).to.eq('0x12345678123456781234567812345678');
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popUint128 full', async () => {
      const result = await test.popUint128('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value.toHexString()).to.eq('0x17181920212223242526272829303132');
      expect(result.inputUpdated).to.eq(bytes32('0x01020304050607080910111213141516'));
    });

    it('popBool', async () => {
      const result = await test.popBool(bytes32(1));

      expect(result.value).to.eq(true);
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popBool bad value', async () => {
      const result = await test.popBool(bytes32(2));

      expect(result.value).to.eq(true);
      expect(result.inputUpdated).to.eq(bytes32(0));
    });

    it('popBool full', async () => {
      const result = await test.popBool('0x0102030405060708091011121314151617181920212223242526272829303132');

      expect(result.value).to.eq(true);
      expect(result.inputUpdated).to.eq(bytes32('0x01020304050607080910111213141516171819202122232425262728293031'));
    });
  });
});
