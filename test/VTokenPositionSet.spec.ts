import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest, ClearingHouse } from '../typechain';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';
const vBaseAddress = '0xF1A16031d66de124735c920e1F2A6b28240C1A5e';
describe('VTokenPosition Library', () => {
  let VTokenPositionSet: VTokenPositionSetTest;
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

    const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
    VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
  });

  describe('Functions', () => {
    it('Activate', async () => {
      await VTokenPositionSet.init(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(0);
      expect(resultVBase[0]).to.eq(0);
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
      expect(resultVToken[0]).to.eq(20);
      expect(resultVToken[2]).to.eq(30);
      expect(resultVBase[0]).to.eq(10);
    });

    it('Realised Funding Payment', async () => {
      await VTokenPositionSet.realizeFundingPaymentToAccount(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[1]).to.eq(0); //sumAChk
      expect(resultVBase[0]).to.eq(10); // Update this after compl getExtraPolatedSumA
    });

    it('abs', async () => {
      expect(await VTokenPositionSet.abs(-10)).to.eq(10);
      expect(await VTokenPositionSet.abs(10)).to.eq(10);
    });
  });
});
