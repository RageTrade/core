import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest, ClearingHouse, VBase, VPoolWrapper } from '../typechain-types';
import { config } from 'dotenv';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
config();
const { ALCHEMY_KEY } = process.env;

const vBaseAddress = '0xF1A16031d66de124735c920e1F2A6b28240C1A5e';
const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
describe('VTokenPositionSet Library', () => {
  // const vTokenAddress: string = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  // const vTokenAddress1: string = utils.hexZeroPad(BigNumber.from(2).toHexString(), 20);
  let VTokenPositionSet: VTokenPositionSetTest;
  let vTokenAddress: string;
  let vTokenAddress1: string;
  let VPoolFactory: ClearingHouse;
  let VBase: VBase;
  let VPoolWrapper: VPoolWrapper;

  before(async () => {
    await activateMainnetFork();

    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy();
    const oracleAddress = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;
    VPoolFactory = await (await hre.ethers.getContractFactory('ClearingHouse')).deploy();

    await VBase.transferOwnership(VPoolFactory.address);
    await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracleAddress, 2, 3, 2);

    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    vTokenAddress = events[0].args[1];
    // console.log('vTokenAddres', vTokenAddress);
    // console.log('VPoolFactoryAddress', VPoolFactory.address);
    // console.log('Vwrapper', events[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);
    await VPoolWrapper.liquidityChange(-10, 10, 10000000000000);

    await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracleAddress, 2, 3, 2);

    const eventFilter1 = VPoolFactory.filters.poolInitlized();
    const events1 = await VPoolFactory.queryFilter(eventFilter1, 'latest');
    vTokenAddress1 = events1[0].args[1];
    // console.log('vTokenAddres1', vTokenAddress);
    // console.log('VPoolFactoryAddress1', VPoolFactory.address);
    // console.log('Vwrapper1', events1[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events1[0].args[2]);
    await VPoolWrapper.liquidityChange(-10, 10, 10000000000000);

    const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
    VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
  });

  after(deactivateMainnetFork);

  describe('Functions', () => {
    it('Activate', async () => {
      await VTokenPositionSet.init(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVBase.balance).to.eq(0);
    });

    it('Update', async () => {
      await VTokenPositionSet.update(
        {
          vBaseIncrease: 10,
          vTokenIncrease: 20,
          traderPositionIncrease: 30,
        },
        vTokenAddress,
      );
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(20);
      expect(resultVToken.netTraderPosition).to.eq(30);
      expect(resultVBase.balance).to.eq(10);
    });

    it('Realized Funding Payment', async () => {
      await VTokenPositionSet.realizeFundingPaymentToAccount(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[1]).to.eq(20); //sumAChk
      expect(resultVBase.balance).to.eq(-590);
    });

    it('abs', async () => {
      expect(await VTokenPositionSet.abs(-10)).to.eq(10);
      expect(await VTokenPositionSet.abs(10)).to.eq(10);
    });
  });

  describe('Token Swaps (Token Amount)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress, 4);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenAmount(vTokenAddress1, 2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVBase.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Token Swaps (Token Notional)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress, 16000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(4);
      expect(resultVToken.netTraderPosition).to.eq(4);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.false;

      await VTokenPositionSet.swapTokenNotional(vTokenAddress1, 8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.be.true;
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(2);
      expect(resultVToken.netTraderPosition).to.eq(2);
      expect(resultVBase.balance).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.true;
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken.balance).to.eq(0);
      expect(resultVToken.netTraderPosition).to.eq(0);
      expect(resultVBase.balance).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.be.false;
    });
  });

  describe('Liquidity Change - 1', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
    });

    it('Add Liquidity');
    // , async () => {
    //   await VTokenPositionSet.liquidityChange1(vTokenAddress, 100);
    //   const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
    //   const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

    //   expect(resultVToken.balance).to.eq(-100);
    //   // expect(resultVToken.netTraderPosition).to.eq(-100);
    //   expect(resultVBase.balance).to.eq(-400000);
    // });

    it('Remove Liquidity');
    // , async () => {
    //   await VTokenPositionSet.liquidityChange1(vTokenAddress, -50);
    //   const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
    //   const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

    //   expect(resultVToken.balance).to.eq(-50);
    //   // expect(resultVToken.netTraderPosition).to.eq(-50);
    //   expect(resultVBase.balance).to.eq(-200000);
    // });
  });

  describe('Liquidity Change - 2', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
    });

    it('Add Liquidity');
    // , async () => {
    //   await VTokenPositionSet.liquidityChange2(vTokenAddress, -50, 50, 100);
    //   const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
    //   const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

    //   expect(resultVToken.balance).to.eq(-100);
    //   // expect(resultVToken.netTraderPosition).to.eq(-100);
    //   expect(resultVBase.balance).to.eq(-400000);
    // });

    it('Remove Liquidity');
    // , async () => {
    //   await VTokenPositionSet.liquidityChange2(vTokenAddress, -50, 50, -50);
    //   const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
    //   const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

    //   expect(resultVToken.balance).to.eq(-50);
    //   // expect(resultVToken.netTraderPosition).to.eq(-50);
    //   expect(resultVBase.balance).to.eq(-200000);
    // });
  });
});
