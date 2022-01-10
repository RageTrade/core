import { config } from 'dotenv';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { ArbitrumFixFeeTest__factory, ClearingHouse } from '../typechain-types';
import { ArbitrumFixFeeTest } from '../typechain-types/ArbitrumFixFeeTest';
import { activateMainnetFork } from './utils/mainnet-fork';
import { setupClearingHouse } from './utils/setup-clearinghouse';

import { wrapEthersProvider } from 'hardhat-tracer/dist/src/wrapper';
import { expect } from 'chai';

config();
const { ALCHEMY_KEY, PRIVATE_KEY } = process.env;

if (!PRIVATE_KEY) {
  throw new Error('Please add PRIVATE_KEY env that contains Arbitrum Rinkeby ETH');
}

const provider = wrapEthersProvider(
  new ethers.providers.StaticJsonRpcProvider('https://arb-rinkeby.g.alchemy.com/v2/' + ALCHEMY_KEY),
  hre.artifacts,
);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

describe('Arbitrum Fix Fee', () => {
  // let clearingHouse: ClearingHouse;
  let test: ArbitrumFixFeeTest;

  before(async () => {
    test = await new ArbitrumFixFeeTest__factory(signer).deploy();

    // const setup = await setupClearingHouse({});
    // const { accountLib, upgradeClearingHouse, vPoolFactory, rBase, insuranceFund } = setup;
    // clearingHouse = setup.clearingHouse;

    // const clearingHouseLogic = await (
    //   await hre.ethers.getContractFactory('ClearingHouse', {
    //     libraries: {
    //       Account: accountLib.address,
    //     },
    //   })
    // ).deploy(vPoolFactory.address, rBase.address, insuranceFund.address);

    // upgradeClearingHouse(clearingHouseLogic.address);
  });

  describe('#getGasCostWei', () => {
    it('gives a value', async () => {
      await test.emitGasCostWei();

      const events = await test.queryFilter(test.filters.Uint());
      expect(events[events.length - 1].args.val).to.be.gt(0);
    });

    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x',
    //   });
    // });
    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x121212',
    //   });
    // });
    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x12121212',
    //   });
    // });
    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x1212121212',
    //   });
    // });
    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x1212121212121212',
    //   });
    // });
    // it('chec2k', async () => {
    //   await signer.sendTransaction({
    //     to: test.address,
    //     data: '0x' + '11'.repeat(32),
    //   });
    // });
  });
});
