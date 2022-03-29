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
    expect(await test['extsload(uint256)'](toUint256(3))).to.eq(toUint256(9));
    expect(await test['extsload(uint256)'](toUint256(4))).to.eq(toUint256(16));
    expect(await test['extsload(uint256)'](toUint256(5))).to.eq(toUint256(25));
  });

  it('reads multiple', async () => {
    expect(await test['extsload(uint256[])']([toUint256(3)])).to.deep.equal([toUint256(9)]);
    expect(await test['extsload(uint256[])']([toUint256(4)])).to.deep.equal([toUint256(16)]);
    expect(await test['extsload(uint256[])']([toUint256(5)])).to.deep.equal([toUint256(25)]);

    expect(await test['extsload(uint256[])']([toUint256(3), toUint256(4)])).to.deep.equal([
      toUint256(9),
      toUint256(16),
    ]);
    expect(await test['extsload(uint256[])']([toUint256(4), toUint256(5)])).to.deep.equal([
      toUint256(16),
      toUint256(25),
    ]);
    expect(await test['extsload(uint256[])']([toUint256(3), toUint256(5)])).to.deep.equal([
      toUint256(9),
      toUint256(25),
    ]);

    expect(await test['extsload(uint256[])']([toUint256(3), toUint256(4), toUint256(5)])).to.deep.equal([
      toUint256(9),
      toUint256(16),
      toUint256(25),
    ]);
  });

  function toUint256(num: number) {
    return BigNumber.from(num);
  }
});
