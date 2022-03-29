import { FakeContract, smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';

import { ERC20, VQuote } from '../../../typechain-types';

describe('VQuote', () => {
  let vQuote: VQuote;
  let signers: SignerWithAddress[];

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    vQuote = await (await hre.ethers.getContractFactory('VQuote')).deploy(10);
    await vQuote.authorize(signers[0].address);
  });

  describe('#decimals', () => {
    it('sets decimals correctly', async () => {
      expect(await vQuote.decimals()).to.eq(10);
    });
  });

  const addr = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';

  describe('#authorise', () => {
    it('works', async () => {
      expect(await vQuote.isAuth(addr)).to.be.false;
      await vQuote.authorize(addr);
      expect(await vQuote.isAuth(addr)).to.be.true;
    });

    it('onlyOwner', async () => {
      expect(vQuote.connect(signers[1]).authorize(addr)).revertedWith('Ownable: caller is not the owner');
    });
  });

  describe('#mint', () => {
    it('works', async () => {
      await vQuote.mint(addr, 10);
      expect(await vQuote.balanceOf(addr)).to.eq(10);
    });

    it('unauthorised', async () => {
      expect(vQuote.connect(signers[1]).mint(addr, 10)).revertedWith('Unauthorised()');
    });
  });

  describe('#burn', () => {
    it('works', async () => {
      await vQuote.mint(signers[0].address, 15);

      await vQuote.burn(5);
      expect(await vQuote.balanceOf(signers[0].address)).to.eq(10);
    });
  });
});
