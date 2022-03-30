import { FakeContract, smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'ethers';
import hre from 'hardhat';

import { ERC20, VToken } from '../../typechain-types';

describe('VToken contract', () => {
  let vToken: VToken;
  let signers: SignerWithAddress[];

  beforeEach(async () => {
    signers = await hre.ethers.getSigners();

    vToken = await (await hre.ethers.getContractFactory('VToken')).deploy('', '', 17);

    await vToken.setVPoolWrapper(signers[0].address);
  });

  describe('#decimals', () => {
    it('sets decimals correctly', async () => {
      expect(await vToken.decimals()).to.eq(17);
    });
  });

  const addr = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';

  describe('#mint', () => {
    it('works', async () => {
      await vToken.mint(addr, 10);
      const bal = await vToken.balanceOf(addr);
      expect(bal).to.eq(10);
    });

    it('unauthorised', async () => {
      expect(vToken.connect(signers[1]).mint(addr, 10)).revertedWith('Unauthorised()');
    });

    describe('#burn', () => {
      it('works', async () => {
        await vToken.mint(signers[0].address, 15);

        await vToken.burn(5);
        const bal = await vToken.balanceOf(signers[0].address);
        expect(bal).to.eq(10);
      });
    });
  });
});
