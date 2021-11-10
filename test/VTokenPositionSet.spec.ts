import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { BigNumber, utils } from 'ethers';
import { VTokenPositionSetTest, ClearingHouse, VToken } from '../typechain';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

const vBaseAddress = '0xF1A16031d66de124735c920e1F2A6b28240C1A5e';

describe('VTokenPositionSet Library', () => {
  let VTokenPositionSet: VTokenPositionSetTest;
  const vTokenAddress: string = utils.hexZeroPad(BigNumber.from(1).toHexString(), 20);
  const vTokenAddress1: string = utils.hexZeroPad(BigNumber.from(2).toHexString(), 20);

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

  describe('getPosition', () => {
    // it('Initialized Position', async() => {
    // });
    // it('Uninitialized Position', async() => {
    // });
  });

  describe('Token Swaps (Token Amount)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(false);

      await VTokenPositionSet.swapTokenAmount(vTokenAddress, 4);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(4);
      expect(resultVToken[2]).to.eq(4);
      expect(resultVBase[0]).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(true);
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.eq(false);

      await VTokenPositionSet.swapTokenAmount(vTokenAddress1, 2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(2);
      expect(resultVToken[2]).to.eq(2);
      expect(resultVBase[0]).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.eq(true);
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(2);
      expect(resultVToken[2]).to.eq(2);
      expect(resultVBase[0]).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(true);
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenAmount(vTokenAddress, -2);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(0);
      expect(resultVToken[2]).to.eq(0);
      expect(resultVBase[0]).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(false);
    });
  });

  describe('Token Swaps (Token Notional)', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
    });

    it('Token1', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(false);

      await VTokenPositionSet.swapTokenNotional(vTokenAddress, 16000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(4);
      expect(resultVToken[2]).to.eq(4);
      expect(resultVBase[0]).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(true);
    });

    it('Token2', async () => {
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.eq(false);

      await VTokenPositionSet.swapTokenNotional(vTokenAddress1, 8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress1);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(2);
      expect(resultVToken[2]).to.eq(2);
      expect(resultVBase[0]).to.eq(-24000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress1)).to.eq(true);
    });

    it('Token1 Partial Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(2);
      expect(resultVToken[2]).to.eq(2);
      expect(resultVBase[0]).to.eq(-16000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(true);
    });

    it('Token1 Close', async () => {
      await VTokenPositionSet.swapTokenNotional(vTokenAddress, -8000);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);
      expect(resultVToken[0]).to.eq(0);
      expect(resultVToken[2]).to.eq(0);
      expect(resultVBase[0]).to.eq(-8000);
      expect(await VTokenPositionSet.getIsActive(vTokenAddress)).to.eq(false);
    });
  });

  describe('Liquidity Change - 1', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
    });

    it('Add Liquidity', async () => {
      await VTokenPositionSet.liquidityChange1(vTokenAddress, 100);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

      expect(resultVToken[0]).to.eq(-100);
      // expect(resultVToken[2]).to.eq(-100);
      expect(resultVBase[0]).to.eq(-400000);
    });

    it('Remove Liquidity', async () => {
      await VTokenPositionSet.liquidityChange1(vTokenAddress, -50);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

      expect(resultVToken[0]).to.eq(-50);
      // expect(resultVToken[2]).to.eq(-50);
      expect(resultVBase[0]).to.eq(-200000);
    });
  });

  describe('Liquidity Change - 2', () => {
    before(async () => {
      const factory = await hre.ethers.getContractFactory('VTokenPositionSetTest');
      VTokenPositionSet = (await factory.deploy()) as unknown as VTokenPositionSetTest;
      await VTokenPositionSet.init(vTokenAddress);
    });

    it('Add Liquidity', async () => {
      await VTokenPositionSet.liquidityChange2(vTokenAddress, -50, 50, 100);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

      expect(resultVToken[0]).to.eq(-100);
      // expect(resultVToken[2]).to.eq(-100);
      expect(resultVBase[0]).to.eq(-400000);
    });

    it('Remove Liquidity', async () => {
      await VTokenPositionSet.liquidityChange2(vTokenAddress, -50, 50, -50);
      const resultVToken = await VTokenPositionSet.getPositionDetails(vTokenAddress);
      const resultVBase = await VTokenPositionSet.getPositionDetails(vBaseAddress);

      expect(resultVToken[0]).to.eq(-50);
      // expect(resultVToken[2]).to.eq(-50);
      expect(resultVBase[0]).to.eq(-200000);
    });
  });
});
