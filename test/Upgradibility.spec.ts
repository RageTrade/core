import { expect } from 'chai';
import hre from 'hardhat';
import { getCreateAddressFor } from './utils/create-addresses';
import { setupClearingHouse } from './utils/setup-clearinghouse';

describe('Upgradibility', () => {
  it('upgrades clearing house logic', async () => {
    const { signer, clearingHouse, rBase, insuranceFund, rageTradeFactory, accountLib } = await setupClearingHouse({});
    expect(await clearingHouse.insuranceFundAddress()).to.eq(insuranceFund.address);

    const newCHAddress = await getCreateAddressFor(signer, 1);
    const newInsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(rBase.address, newCHAddress);

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

  it('upgrades vpoolwrapper');
});
