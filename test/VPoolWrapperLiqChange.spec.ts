import hre from 'hardhat';
import { network } from 'hardhat';
import { ClearingHouse, VBase, VPoolWrapper } from '../typechain';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;
const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

describe('VPoolWrapper', () => {
  let oracle: string;
  let VBase: VBase;
  let VPoolFactory: ClearingHouse;
  let VPoolWrapper: VPoolWrapper;
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

    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy();
    oracle = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;
    VPoolFactory = await (await hre.ethers.getContractFactory('ClearingHouse')).deploy();
    VBase.transferOwnership(VPoolFactory.address);

    await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracle, 2, 3, 60);
    const eventFilter = VPoolFactory.filters.poolInitlized();
    const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
    const vPoolWrapperAddress = events[0].args[2];
    VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', vPoolWrapperAddress);
  });

  describe('Liquidity Change', () => {
    it('Add Liquidity', async () => {});
    it('Remove Liquidity', async () => {});
  });
});
