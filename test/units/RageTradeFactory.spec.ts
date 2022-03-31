import { expect } from 'chai';
import { BigNumber, ethers } from 'ethers';
import hre from 'hardhat';

import { smock } from '@defi-wonderland/smock';

import { ERC20 } from '../../typechain-types';
import { activateMainnetFork, deactivateMainnetFork } from '../helpers/mainnet-fork';
import { initializePool, setupClearingHouse } from '../helpers/setup-clearinghouse';

describe('RageTradeFactory', () => {
  // before(activateMainnetFork);
  // TODO: for some weird reason above doesn't resolve. figure out why later.
  before(async () => {
    await activateMainnetFork();
  });
  after(deactivateMainnetFork);

  describe('#constructor', () => {
    it('deploys VQuote at good address', async () => {
      for (let i = 0; i < 5; i++) {
        const { vQuote } = await setupClearingHouse({});
        expect(vQuote.address[2].toLowerCase()).to.eq('f');
      }
    });

    // TODO add this test case
    it.skip('initializes values', async () => {
      const { vQuote, clearingHouse } = await setupClearingHouse({});
      // expect(await clearingHouse.vQuote)
    });

    it('governance and teamMultisig is deployer', async () => {
      let { clearingHouse, rageTradeFactory, signer } = await setupClearingHouse({});

      expect(await rageTradeFactory.governance()).to.eq(signer.address);
      expect(await rageTradeFactory.teamMultisig()).to.eq(signer.address);

      expect(await clearingHouse.governance()).to.eq(signer.address);
      expect(await clearingHouse.teamMultisig()).to.eq(signer.address);
    });

    it('sets proxyAdmin owner', async () => {
      let { proxyAdmin, signer } = await setupClearingHouse({});
      expect(await proxyAdmin.owner()).to.eq(signer.address);
    });
  });

  describe('#initializePool', () => {
    it('deploys vToken at good address', async () => {
      let { rageTradeFactory, vQuote } = await setupClearingHouse({});

      // todo change cTokenAddress requirement to cTokenDecimals
      const realToken = await smock.fake<ERC20>('ERC20');
      realToken.decimals.returns(18);

      const oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();
      await rageTradeFactory.initializePool({
        deployVTokenParams: {
          vTokenName: 'vTest',
          vTokenSymbol: 'vTest',
          cTokenDecimals: 18,
        },
        poolInitialSettings: {
          initialMarginRatioBps: 1,
          maintainanceMarginRatioBps: 2,
          maxVirtualPriceDeviationRatioBps: 10000,
          twapDuration: 3,
          isAllowedForTrade: false,
          isCrossMargined: false,
          oracle: oracle.address,
        },
        liquidityFeePips: 500,
        protocolFeePips: 500,
        slotsToInitialize: 100,
      });

      const eventFilter = rageTradeFactory.filters.PoolInitialized();
      const events = await rageTradeFactory.queryFilter(eventFilter, 'latest');

      // vTokenAddress should be such that in UniswapV3Pool it becomes token0 always
      const vTokenAddress = events[0].args.vToken;
      expect(BigNumber.from(vTokenAddress).lt(vQuote.address)).to.be.true;
    });
  });

  describe('#upgradability', () => {
    it('upgrades clearing house logic', async () => {
      const { clearingHouse, proxyAdmin, accountLib } = await setupClearingHouse({});

      const newCHLogic = await (
        await hre.ethers.getContractFactory('ClearingHouseDummy', {
          libraries: {
            Account: accountLib.address,
          },
        })
      ).deploy();

      await proxyAdmin.upgrade(clearingHouse.address, newCHLogic.address);

      const clearingHouse_ = await hre.ethers.getContractAt('ClearingHouseDummy', clearingHouse.address);

      expect(await clearingHouse_.newMethodAdded()).to.eq(1234567890);
    });

    it('upgrades vpoolwrapper', async () => {
      const { rageTradeFactory, proxyAdmin } = await setupClearingHouse({});

      const { vPoolWrapper } = await initializePool({ rageTradeFactory });

      // blockTimestamp method does not exist on vPoolWrapper
      const _vPoolWrapper = await hre.ethers.getContractAt('VPoolWrapperMockRealistic', vPoolWrapper.address);
      await expect(_vPoolWrapper.blockTimestamp()).to.be.revertedWith(
        "function selector was not recognized and there's no fallback function",
      );

      // upgrading the logic to include the blockTimestamp method
      const newVPoolWrapperLogic = await (await hre.ethers.getContractFactory('VPoolWrapperMockRealistic')).deploy();
      // await rageTradeFactory.setVPoolWrapperLogicAddress(newVPoolWrapperLogic.address);
      await proxyAdmin.upgrade(_vPoolWrapper.address, newVPoolWrapperLogic.address);
      expect(await _vPoolWrapper.blockTimestamp()).to.eq(0);

      // updating address in rage trade factory
      await rageTradeFactory.setVPoolWrapperLogicAddress(newVPoolWrapperLogic.address);
      expect(await rageTradeFactory.vPoolWrapperLogicAddress()).to.eq(newVPoolWrapperLogic.address);

      await expect(rageTradeFactory.setVPoolWrapperLogicAddress(ethers.constants.AddressZero)).to.be.revertedWith(
        'IllegalAddress("0x0000000000000000000000000000000000000000")',
      );
    });
  });
});
