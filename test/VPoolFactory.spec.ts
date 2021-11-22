import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { VPoolFactory, VPoolWrapperDeployer, ERC20, UtilsTest, VBase } from '../typechain-types';
import { getCreate2Address, getCreate2Address2 } from './utils/create2';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { utils } from 'ethers';
import { config } from 'dotenv';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { smock } from '@defi-wonderland/smock';
config();
const { ALCHEMY_KEY } = process.env;

const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

describe('VPoolFactory', () => {
  let oracle: string;
  let VBase: VBase;
  let VPoolFactory: VPoolFactory;
  let VPoolWrapperDeployer: VPoolWrapperDeployer;
  let UtilsTestContract: UtilsTest;
  let vTokenByteCode: string;
  let VPoolWrapperByteCode: string;

  before(async () => {
    await activateMainnetFork();

    const realToken = await smock.fake<ERC20>('ERC20');
    realToken.decimals.returns(10);
    VBase = await (await hre.ethers.getContractFactory('VBase')).deploy(realToken.address);
    oracle = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;
    VPoolWrapperDeployer = await (await hre.ethers.getContractFactory('VPoolWrapperDeployer')).deploy();
    VPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      VBase.address,
      VPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );
    await VBase.transferOwnership(VPoolFactory.address);
    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse')
    ).deploy(VPoolFactory.address, REAL_BASE);
    await VPoolFactory.initBridge(clearingHouse.address);
    UtilsTestContract = await (await hre.ethers.getContractFactory('UtilsTest')).deploy();

    VPoolWrapperByteCode = (await hre.ethers.getContractFactory('VPoolWrapper')).bytecode;
    vTokenByteCode = (await hre.ethers.getContractFactory('VToken')).bytecode;
  });

  after(deactivateMainnetFork.bind(null, hre));

  describe('Initilize', () => {
    it('Deployments', async () => {
      await VPoolFactory.initializePool('vWETH', 'vWETH', realToken, oracle, 2, 3, 60);
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
            ['vWETH', 'vWETH', realToken, oracle, VPoolFactory.address],
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
      const vToken_state_owner = await vToken.owner();

      expect(vToken_state_name).to.eq('vWETH');
      expect(vToken_state_symbol).to.eq('vWETH');
      expect(vToken_state_realToken.toLowerCase()).to.eq(realToken);
      expect(vToken_state_oracle).to.eq(oracle);
      expect(vToken_state_owner.toLowerCase()).to.eq(vPoolWrapper.toLowerCase());

      // VPool : Create2
      if (VBase.address.toLowerCase() < vTokenAddress.toLowerCase())
        salt = utils.defaultAbiCoder.encode(['address', 'address', 'uint24'], [VBase.address, vTokenAddress, 500]);
      else salt = utils.defaultAbiCoder.encode(['address', 'address', 'uint24'], [vTokenAddress, VBase.address, 500]);
      const vPoolCalculated = getCreate2Address2(UNISWAP_FACTORY_ADDRESS, salt, POOL_BYTE_CODE_HASH);
      expect(vPool).to.eq(vPoolCalculated);

      // VPoolWrapper : Create2
      salt = utils.defaultAbiCoder.encode(['address', 'address'], [vTokenAddress, VBase.address]);
      const vPoolWrapperCalculated = getCreate2Address(VPoolWrapperDeployer.address, salt, VPoolWrapperByteCode);
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
