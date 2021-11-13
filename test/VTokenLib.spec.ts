import { expect } from 'chai';
import hre from 'hardhat';

import { VTokenLibTest } from '../typechain';
const vTokenAdddres = '0xbb72710011FE06C29B9D5817952482b521812E09';
const vPoolAddress = '0x198A9653be67B78e4B59c2BabFfa9b4Db4dAcB81';
const vPoolWrapper = '0x27bdca824a63716e30e9295f2da41c8f6a6ed794';
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

    it('flip', async () => {
      const result = await vTokenLib.flip(vTokenAdddres, 20, 30);
      expect(result[0]).to.eq(30); //BaseAmnt
      expect(result[1]).to.eq(20); //VTokenAmnt
    });

    it('vPool', async () => {
      const result = await vTokenLib.vPool(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolAddress.toLowerCase());
    });

    it('vPoolWrapper', async () => {
      const result = await vTokenLib.vPoolWrapper(vTokenAdddres);
      expect(result.toLowerCase()).to.eq(vPoolWrapper.toLowerCase());
    });
  });
});
