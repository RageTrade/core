import { Signer } from '@ethersproject/abstract-signer';
import { expect } from 'chai';
import hre from 'hardhat';

import { VToken } from '../typechain-types';

describe('VToken contract', () => {
  let VToken: VToken;
  let signers: Signer[];
  let signer0Address: string;
  let signer1Address: string;
  before(async () => {
    signers = await hre.ethers.getSigners();
    signer0Address = await signers[0].getAddress();
    signer1Address = await signers[1].getAddress();
    VToken = await (
      await hre.ethers.getContractFactory('VToken')
    ).deploy('', '', signer1Address, signer1Address, signer1Address);

    await VToken.setOwner(signer1Address);
  });

  describe('Functions', () => {
    it('Mint Unsuccessful', async () => {
      expect(VToken.mint(signer0Address, 10)).revertedWith('Unauthorised()');
    });

    it('Mint Successful', async () => {
      await VToken.connect(signers[1]).mint(signer0Address, 10);
      const bal = await VToken.balanceOf(signer0Address);
      expect(bal).to.eq(10);
    });

    it('Burn Successful', async () => {
      await VToken.burn(5);
      const bal = await VToken.balanceOf(signer0Address);
      expect(bal).to.eq(5);
    });
  });
});
