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
  let VTokenPositionSet: VTokenPositionSetTest;
  let vTokenAddress: string;
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
    console.log('vTokenAddres', vTokenAddress);
    console.log('VPoolFactoryAddress', VPoolFactory.address);
    console.log('Vwrapper', events[0].args[2]);
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', events[0].args[2]);
    await VPoolWrapper.liquidityChange(-10, 10, 10000000000000);
    const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
    VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
  });

  after(deactivateMainnetFork);

  describe('Functions', () => {
    it('GetAllTokenPositionValueAndMargin, Single', async () => {
      await VTokenPositionSet.init(vTokenAddress);
      await VTokenPositionSet.update(
        {
          vBaseIncrease: 10,
          vTokenIncrease: 20,
          traderPositionIncrease: 30,
        },
        vTokenAddress,
      );
      const result = await VTokenPositionSet.getAllTokenPositionValueAndMargin(true);
      console.log(result);
    });
  });
});
