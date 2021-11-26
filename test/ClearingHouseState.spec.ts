import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ClearingHouse } from '../typechain-types';
import { REAL_BASE } from './utils/realConstants';
import { expect } from 'chai';
import hre from 'hardhat';
import { constants } from './utils/dummyConstants';

describe('ClearingHouseState', () => {
  let signers: SignerWithAddress[];
  let state: ClearingHouse;
  const dummyAdd = '0xbb72710011FE06C29B9D5817952482b521812E09';
  before(async () => {
    signers = await hre.ethers.getSigners();
    state = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(await signers[0].getAddress(), REAL_BASE, dummyAdd);
  });

  describe('Functions', () => {
    it('AddKey and isKeyAvailable', async () => {
      expect(await state.connect(signers[1]).isKeyAvailable(2)).to.be.true;
      expect(state.connect(signers[1]).addKey(2, dummyAdd)).revertedWith('NotVPoolFactory()');
      await state.addKey(2, dummyAdd);
      expect(await state.connect(signers[1]).isKeyAvailable(2)).to.be.false;
    });
    it('initRealToken and isRealTokenAlreadyInitilized', async () => {
      expect(await state.connect(signers[1]).isRealTokenAlreadyInitilized(dummyAdd)).to.be.false;
      expect(state.connect(signers[1]).initRealToken(dummyAdd)).revertedWith('NotVPoolFactory()');
      await state.initRealToken(dummyAdd);
      expect(await state.connect(signers[1]).isRealTokenAlreadyInitilized(dummyAdd)).to.be.true;
    });
    it('setConstants', async () => {
      expect(state.connect(signers[1]).setConstants(constants)).revertedWith('NotVPoolFactory()');
      await state.setConstants(constants);
    });
  });
});
