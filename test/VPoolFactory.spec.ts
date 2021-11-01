import { expect } from 'chai';
import hre from 'hardhat';
import { network, ethers, deployments } from 'hardhat';
import { ClearingHouse, UtilsTest } from '../typechain';
import { getCreate2Address, getCreate2Address2 } from './utils/create2';
import { utils } from 'ethers';
import { config } from 'dotenv';
config();
const { ALCHEMY_KEY } = process.env;

const UNISWAP_FACTORY_ADDRESS = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const POOL_BYTE_CODE_HASH = '0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54';
const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

describe('VPoolFactory', () => {
  let oracleContract: string;
  let VPoolFactory: ClearingHouse;
  let UtilsTestContract: UtilsTest;
  let vTokenByteCode: string;
  let VPoolWrapperByteCode: string;

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
    oracleContract = (await (await hre.ethers.getContractFactory('OracleContract')).deploy()).address;
    VPoolFactory = await (await hre.ethers.getContractFactory('ClearingHouse')).deploy();
    UtilsTestContract = await (await hre.ethers.getContractFactory('UtilsTest')).deploy();

    VPoolWrapperByteCode = (await hre.ethers.getContractFactory('VPoolWrapper')).bytecode;
    vTokenByteCode = (await hre.ethers.getContractFactory('VToken')).bytecode;
  });

  describe('Initilize', () => {
    it('Deployments', async () => {
      await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracleContract, 2, 3, 60);
      const eventFilter = VPoolFactory.filters.poolInitlized();
      const events = await VPoolFactory.queryFilter(eventFilter, 'latest');
      const vPool = events[0].args[0];
      const vTokenAddress = events[0].args[1];
      const vPoolWrapper = events[0].args[2];

      //console.log(vTokenAddress, vPool, vPoolWrapper);
      // VToken : Create2
      const saltInUint160 = await UtilsTestContract.convertAddressToUint160(realToken);
      let salt = utils.defaultAbiCoder.encode(['uint160'], [saltInUint160]);
      let bytecode = utils.solidityPack(
        ['bytes', 'bytes'],
        [
          vTokenByteCode,
          utils.defaultAbiCoder.encode(
            ['string', 'string', 'address', 'address', 'address'],
            ['vWETH', 'vWETH', realToken, oracleContract, VPoolFactory.address],
          ),
        ],
      );
      const vTokenComputedAddress = getCreate2Address(VPoolFactory.address, salt, bytecode);
      expect(vTokenAddress).to.eq(vTokenComputedAddress);

      // VToken : Cons Params
      const vToken = await hre.ethers.getContractAt('VToken', vTokenAddress);
      const vToken_state_name = await vToken.name();
      const vToken_state_symbol = await vToken.symbol();
      const vToken_state_realToken = await vToken.realToken();
      const vToken_state_oracle = await vToken.oracle();
      const vToken_state_perpState = await vToken.perpState();

      expect(vToken_state_name).to.eq('vWETH');
      expect(vToken_state_symbol).to.eq('vWETH');
      expect(vToken_state_realToken.toLowerCase()).to.eq(realToken);
      expect(vToken_state_oracle).to.eq(oracleContract);
      expect(vToken_state_perpState.toLowerCase()).to.eq(VPoolFactory.address.toLowerCase());

      // VPool : Create2
      const vBase = await UtilsTestContract.getVBase();
      salt = utils.defaultAbiCoder.encode(['address', 'address', 'uint24'], [vTokenAddress, vBase, 500]);
      const vPoolCalculated = getCreate2Address2(UNISWAP_FACTORY_ADDRESS, salt, POOL_BYTE_CODE_HASH);
      expect(vPool).to.eq(vPoolCalculated);

      // VPoolWrapper : Create2
      salt = utils.defaultAbiCoder.encode(['address', 'address'], [vTokenAddress, vBase]);
      const vPoolWrapperCalculated = getCreate2Address(VPoolFactory.address, salt, VPoolWrapperByteCode);
      expect(vPoolWrapper).to.eq(vPoolWrapperCalculated);

      // VPoolWrapper : Params
      const VPoolWrapper = await hre.ethers.getContractAt('VPoolWrapper', vPoolWrapper);
      const VPoolWrapper_state_initialMarginRatio = await VPoolWrapper.initialMarginRatio();
      const VPoolWrapper_state_maintainanceMarginRatio = await VPoolWrapper.maintainanceMarginRatio();
      const VPoolWrapper_state_timeHorizon = await VPoolWrapper.timeHorizon();
      expect(VPoolWrapper_state_initialMarginRatio).to.eq(2);
      expect(VPoolWrapper_state_maintainanceMarginRatio).to.eq(3);
      expect(VPoolWrapper_state_timeHorizon).to.eq(60);

      // const eventFilter1 = VPoolFactory.filters.test();
      // const events1 = await VPoolFactory.queryFilter(eventFilter1, 'latest');
      // console.log(events1[0].args[0]);
      // console.log(events1[0].args[1]);
    });
  });
});
