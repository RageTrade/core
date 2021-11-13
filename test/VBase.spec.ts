import { Signer } from '@ethersproject/abstract-signer';
import { expect } from 'chai';
import hre from 'hardhat';

import { VBase } from '../typechain-types';

describe('VBase', () => {
  let VBase: VBase;
  let signers: Signer[];
  let signer0Address: string;
  let signer1Address: string;
  before(async () => {
    signers = await hre.ethers.getSigners();
    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy();
    signer0Address = await signers[0].getAddress();
    signer1Address = await signers[1].getAddress();
  });

  describe('Functions', () => {
    it('Mint Unsuccessful', async () => {
      expect(VBase.mint(signer1Address, 10)).revertedWith('Not Auth');
    });

    it('Burn Unsuccessful', async () => {
      expect(VBase.burn(signer1Address, 10)).revertedWith('Not Auth');
    });

    it('Authorize', async () => {
      expect(VBase.connect(signers[1]).authorize(signer0Address)).revertedWith('Ownable: caller is not the owner');
      await VBase.authorize(signer0Address);
    });

    it('Mint Successful', async () => {
      await VBase.mint(signer1Address, 10);
      const bal = await VBase.balanceOf(signer1Address);
      expect(bal).to.eq(10);
    });

    it('Burn Unsuccessful', async () => {
      await VBase.burn(signer1Address, 5);
      const bal = await VBase.balanceOf(signer1Address);
      expect(bal).to.eq(5);
    });
  });
});
