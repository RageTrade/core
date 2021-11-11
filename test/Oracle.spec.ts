import hre from 'hardhat';

import { OracleTest } from '../typechain-types';

describe('Oracle Library', () => {
  let test: OracleTest;

  beforeEach(async () => {
    const factory = await hre.ethers.getContractFactory('OracleTest');
    test = await factory.deploy();
  });

  describe('#twap', () => {
    it('1 hour', async () => {
      await test.checkPrice();
    });
  });
});
