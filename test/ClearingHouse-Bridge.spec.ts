import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ClearingHouse } from '../typechain-types';
import { REAL_BASE } from './utils/realConstants';
import { expect } from 'chai';
import hre from 'hardhat';
import { constants } from './utils/dummyConstants';

describe('ClearingHouse - Bridge', () => {
  let signers: SignerWithAddress[];
  let bridge: ClearingHouse;
  const dummyAdd = '0xbb72710011FE06C29B9D5817952482b521812E09';
  before(async () => {
    signers = await hre.ethers.getSigners();
    bridge = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(await signers[0].getAddress(), REAL_BASE);
  });

  describe('Functions', () => {
    it('AddKey and isKeyAvailable', async () => {
      expect(await bridge.connect(signers[1]).isKeyAvailable(2)).to.be.true;
      expect(bridge.connect(signers[1]).addKey(2, dummyAdd)).revertedWith('NotVPoolFactory()');
      await bridge.addKey(2, dummyAdd);
      expect(await bridge.connect(signers[1]).isKeyAvailable(2)).to.be.false;
    });
    it('initRealToken and isRealTokenAlreadyInitilized', async () => {
      expect(await bridge.connect(signers[1]).isRealTokenAlreadyInitilized(dummyAdd)).to.be.false;
      expect(bridge.connect(signers[1]).initRealToken(dummyAdd)).revertedWith('NotVPoolFactory()');
      await bridge.initRealToken(dummyAdd);
      expect(await bridge.connect(signers[1]).isRealTokenAlreadyInitilized(dummyAdd)).to.be.true;
    });
    it('setConstants', async () => {
      expect(bridge.connect(signers[1]).setConstants(constants)).revertedWith('NotVPoolFactory()');
      await bridge.setConstants(constants);
    });
  });
});
