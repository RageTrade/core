import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { setupClearingHouse, initializePool } from './utils/setup-clearinghouse';

describe('Upgradibility', () => {
  // before(activateMainnetFork);
  // TODO: for some weird reason above doesn't resolve. figure out why later.
  before(async () => {
    await activateMainnetFork();
  });
  after(deactivateMainnetFork);

  it('upgrades clearing house logic', async () => {
    const { clearingHouse, rageTradeFactory, accountLib } = await setupClearingHouse({});

    const newCHLogic = await (
      await hre.ethers.getContractFactory('ClearingHouseDummy', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy();

    await rageTradeFactory.upgradeClearingHouseToLatestLogic(clearingHouse.address, newCHLogic.address);

    expect(await clearingHouse.getFixFee()).to.eq(1234567890);
  });

  it('upgrades vpoolwrapper', async () => {
    const { clearingHouse, rageTradeFactory, accountLib } = await setupClearingHouse({});

    const { vPoolWrapper } = await initializePool({ rageTradeFactory });

    // blockTimestamp method does not exist on vPoolWrapper
    const _vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapperMockRealistic', vPoolWrapper.address);
    expect(_vPoolWrapper.blockTimestamp()).to.be.revertedWith(
      "function selector was not recognized and there's no fallback function",
    );

    // upgrading the logic to include the blockTimestamp method
    const newVPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapperMockRealistic')).deploy();
    await rageTradeFactory.setVPoolWrapperLogicAddress(newVPoolWrapperLogic.address);
    await rageTradeFactory.upgradeVPoolWrapperToLatestLogic(_vPoolWrapper.address);
    expect(await _vPoolWrapper.blockTimestamp()).to.eq(0);
  });
});
