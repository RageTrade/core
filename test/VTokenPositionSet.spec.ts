import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest, ClearingHouse } from '../typechain';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

const vBaseAddress = '0xF1A16031d66de124735c920e1F2A6b28240C1A5e';

describe('VTokenPositionSet Library', () => {
  let VTokenPositionSet: VTokenPositionSetTest;
  const vTokenAddress: string = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);

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

    it('Realized Funding Payment', async () => {
      await VTokenPositionSet.realizeFundingPaymentToAccount(vTokenAddress);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[1]).to.eq(20); //sumAChk
      expect(resultVBase[0]).to.eq(-590);
    });

    it('abs', async () => {
      expect(await VTokenPositionSet.abs(-10)).to.eq(10);
      expect(await VTokenPositionSet.abs(10)).to.eq(10);
    });
  });
});
