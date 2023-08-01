import { IERC20__factory } from '../../typechain-types/';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import { activateMainnetFork } from '../helpers/mainnet-fork';

describe('Update Implementation', () => {
  before(async () => {
    await activateMainnetFork({
      network: 'arbitrum-mainnet',
      blockNumber: 116800000,
    });
  });

  it('Sunset', async () => {
    const clearingHouseAddr = '0x4521916972A76D5BFA65Fb539Cf7a0C2592050Ac';
    const accountAddr = '0x3fab135e76c5c0e85a60bf50f100c8cd912f7e56';
    const usdc = IERC20__factory.connect('0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', hre.ethers.provider);

    const coreWithLogicAbi = await hre.ethers.getContractAt('ClearingHouse', clearingHouseAddr);
    const coreWithProxyAbi = await hre.ethers.getContractAt('TransparentUpgradeableProxy', clearingHouseAddr);

    const proxyAdmin = '0xA335Dd9CeFBa34449c0A89FB4d247f395C5e3782';
    const timelock = '0x39B54de853d9dca48e928a273c3BB5fa0299540A';

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [proxyAdmin],
    });

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [timelock],
    });

    const timelockSigner = await hre.ethers.getSigner(timelock);
    const proxyAdminSigner = await hre.ethers.getSigner(proxyAdmin);

    const newCoreLogic = await (
      await hre.ethers.getContractFactory('ClearingHouse', {
        libraries: {
          ['contracts/libraries/Account.sol:Account']: accountAddr,
        },
      })
    ).deploy();

    const teamMultisig = await coreWithLogicAbi.teamMultisig();

    await coreWithProxyAbi.connect(proxyAdminSigner).upgradeTo(newCoreLogic.address);
    console.log('core upgraded');

    const usdcBalBefore = await usdc.balanceOf(teamMultisig);
    const usdcBalCore = await usdc.balanceOf(coreWithLogicAbi.address);

    await coreWithLogicAbi.connect(timelockSigner).withdrawUSDCToTeamMultisig();

    const usdcBalAfter = await usdc.balanceOf(teamMultisig);

    expect(await usdc.balanceOf(coreWithLogicAbi.address)).to.eq(0);
    expect(usdcBalAfter).to.eq(usdcBalBefore.add(usdcBalCore));
  });
});
