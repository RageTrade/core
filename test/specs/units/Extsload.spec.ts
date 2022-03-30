import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { hexZeroPad } from 'ethers/lib/utils';
import hre from 'hardhat';
import { ExtsloadTest } from '../../../typechain-types';

describe('Extsload', () => {
  let test: ExtsloadTest;
  before(async () => {
    test = await (await hre.ethers.getContractFactory('ExtsloadTest')).deploy();
  });

  it('reads single', async () => {
    expect(await test['extsload(bytes32)'](toBytes32(3))).to.eq(toBytes32(9));
    expect(await test['extsload(bytes32)'](toBytes32(4))).to.eq(toBytes32(16));
    expect(await test['extsload(bytes32)'](toBytes32(5))).to.eq(toBytes32(25));
  });

  it('reads multiple', async () => {
    expect(await test['extsload(bytes32[])']([toBytes32(3)])).to.deep.equal([toBytes32(9)]);
    expect(await test['extsload(bytes32[])']([toBytes32(4)])).to.deep.equal([toBytes32(16)]);
    expect(await test['extsload(bytes32[])']([toBytes32(5)])).to.deep.equal([toBytes32(25)]);

    expect(await test['extsload(bytes32[])']([toBytes32(3), toBytes32(4)])).to.deep.equal([
      toBytes32(9),
      toBytes32(16),
    ]);
    expect(await test['extsload(bytes32[])']([toBytes32(4), toBytes32(5)])).to.deep.equal([
      toBytes32(16),
      toBytes32(25),
    ]);
    expect(await test['extsload(bytes32[])']([toBytes32(3), toBytes32(5)])).to.deep.equal([
      toBytes32(9),
      toBytes32(25),
    ]);

    expect(await test['extsload(bytes32[])']([toBytes32(3), toBytes32(4), toBytes32(5)])).to.deep.equal([
      toBytes32(9),
      toBytes32(16),
      toBytes32(25),
    ]);
  });

  function toBytes32(num: number) {
    return hexZeroPad(BigNumber.from(num).toHexString(), 32);
  }
});
