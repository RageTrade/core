import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionTest, ClearingHouse } from '../typechain';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

describe('VTokenPosition Library', () => {
  let VTokenPosition: VTokenPositionTest;
  let VPoolFactory: ClearingHouse;
  let vPool: string;
  let vTokenAddress: string;
  let vPoolWrapper: string;
  let priceX96: BigNumber;
  let balance: BigNumber;
  const Q96: BigNumber = BigNumber.from('0x1000000000000000000000000');

  before(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: 'https://eth-mainnet.alchemyapi.io/v2/' + ALCHEMY_KEY,
            blockNumber: 13075000,
          },
        },
      ],
    });

    await (
      await (await hre.ethers.getContractFactory('VBase')).deploy()
    ).address;
    const oracleContract = (await (await hre.ethers.getContractFactory('OracleContract')).deploy()).address;
    VPoolFactory = await (await hre.ethers.getContractFactory('ClearingHouse')).deploy();
    await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracleContract, 2, 3, 60);

    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    vPool = events[0].args[0];
    vTokenAddress = events[0].args[1];
    vPoolWrapper = events[0].args[2];

    const factory = await hre.ethers.getContractFactory('VTokenPositionTest');
    VTokenPosition = (await factory.deploy()) as unknown as VTokenPositionTest;

    priceX96 = BigNumber.from('242445728302062693925');
    balance = BigNumber.from('10').pow(18);

    await VTokenPosition.init(vTokenAddress, balance, -10, 0);
  });

  describe('Functions', () => {
    it('getTokenPositionValue', async () => {
      const result = await VTokenPosition.getTokenPositionValue(priceX96);
      expect(result).to.eq(balance.mul(priceX96).div(Q96));
    });
    it('riskSide', async () => {
      const result = await VTokenPosition.riskSide();
      expect(result).to.eq(0);
    });
  });
});
