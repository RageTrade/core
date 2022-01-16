import { FakeContract, smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';

import { ERC20, VBase } from '../typechain-types';

describe('VBase', () => {
  let vBase: VBase;
  let signers: SignerWithAddress[];

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    vBase = await (await hre.ethers.getContractFactory('VBase')).deploy(10);
    await vBase.authorize(signers[0].address);
  });

  describe('#decimals', () => {
    it('sets decimals correctly', async () => {
      expect(await vBase.decimals()).to.eq(10);
    });
  });

  const addr = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';

  describe('#authorise', () => {
    it('works', async () => {
      expect(await vBase.isAuth(addr)).to.be.false;
      await vBase.authorize(addr);
      expect(await vBase.isAuth(addr)).to.be.true;
    });

    it('onlyOwner', async () => {
      expect(vBase.connect(signers[1]).authorize(addr)).revertedWith('Ownable: caller is not the owner');
    });
  });

  describe('#mint', () => {
    it('works', async () => {
      await vBase.mint(addr, 10);
      expect(await vBase.balanceOf(addr)).to.eq(10);
    });

    it('unauthorised', async () => {
      expect(vBase.connect(signers[1]).mint(addr, 10)).revertedWith('Unauthorised()');
    });
  });

  describe('#burn', () => {
    it('works', async () => {
      await vBase.mint(signers[0].address, 15);

      await vBase.burn(5);
      expect(await vBase.balanceOf(signers[0].address)).to.eq(10);
    });
  });
});
