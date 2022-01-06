import { expect } from 'chai';
import hre from 'hardhat';
import { getCreateAddressFor } from './utils/create-addresses';
import { setupClearingHouse } from './utils/setup-clearinghouse';

describe('Upgradibility', () => {
  it('upgrades to change insurance fund', async () => {
    const { signer, clearingHouse, rBase, insuranceFund, vPoolFactory, accountLib, upgradeClearingHouse } =
      await setupClearingHouse({});
    expect(await clearingHouse.insuranceFundAddress()).to.eq(insuranceFund.address);

    const newCHAddress = await getCreateAddressFor(signer, 1);
    const newInsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(rBase.address, newCHAddress);

    const newCH = await (
      await hre.ethers.getContractFactory('ClearingHouse', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy(vPoolFactory.address, rBase.address, newInsuranceFund.address);
    await upgradeClearingHouse(newCH.address);

    expect(await clearingHouse.insuranceFundAddress()).to.eq(newInsuranceFund.address);
  });
});
