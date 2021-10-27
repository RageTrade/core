import { expect } from 'chai';
import hre from 'hardhat';

import { VTokenLibTest } from '../typechain';
const vTokenAdddres = '0x7d93f6D1214143ed8fef55113DAa923C97be5f14';
const vPoolAddress = '0x039944268d8218c20c3e42eb9712ea0ac4ce589c';
const vPoolWrapper = '0x5685089f7c6bf4cb3e0645f4972cba6d6b142cdc';
const vBaseAddress = '0xcd8a1c3ba11cf5ecfa6267617243239504a98d90';

describe('VTokenLib Library', () => {
  let vTokenLib: VTokenLibTest;
  before(async () => {
    const factory = await hre.ethers.getContractFactory('VTokenLibTest');
    vTokenLib = (await factory.deploy()) as unknown as VTokenLibTest;
  });

  describe('Functions', () => {
    it('isToken0', async () => {
      const result = await vTokenLib.isToken0(vTokenAdddres);
      expect(result).to.be.true;
    });

    it('isToken1', async () => {
      const result = await vTokenLib.isToken1(vTokenAdddres);
      expect(result).to.be.false;
    });

    it('vPool', async () => {
      const result = await vTokenLib.vPool(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolAddress);
    });

    it('vPoolWrapper', async () => {
      const result = await vTokenLib.vPoolWrapper(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolWrapper);
    });
  });
});
