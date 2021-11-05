import { Signer } from '@ethersproject/abstract-signer';
import { expect } from 'chai';
import hre from 'hardhat';

import { VBase } from '../typechain';

describe('VBase', () => {
  let VBase: VBase;
  let signers: Signer[];
  before(async () => {
    signers = await hre.ethers.getSigners();
    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy();
  });

  describe('Functions', () => {
    it('Mint Unsuccessful', async () => {
      const account = await signers[1].getAddress();
      expect(VBase.mint(account, 10)).revertedWith('Not Auth');
    });

    it('Burn Unsuccessful', async () => {
      const account = await signers[1].getAddress();
      expect(VBase.burn(account, 10)).revertedWith('Not Auth');
    });

    it('Authorize', async () => {
      const account = await signers[0].getAddress();
      expect(VBase.connect(signers[1]).authorize(account)).revertedWith('Ownable: caller is not the owner');
      await VBase.authorize(account);
    });

    it('Mint Successful', async () => {
      const account = await signers[1].getAddress();
      await VBase.mint(account, 10);
      const bal = await VBase.balanceOf(account);
      expect(bal).to.eq(10);
    });

    it('Burn Unsuccessful', async () => {
      const account = await signers[1].getAddress();
      await VBase.burn(account, 5);
      const bal = await VBase.balanceOf(account);
      expect(bal).to.eq(5);
    });
  });
});
