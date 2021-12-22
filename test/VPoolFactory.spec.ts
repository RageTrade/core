import { expect } from 'chai';
import hre from 'hardhat';
import { network } from 'hardhat';
import { VPoolFactory, VPoolWrapperDeployer, ERC20, UtilsTest, VBase, IOracle } from '../typechain-types';
import { getCreate2Address, getCreate2Address2 } from './utils/create2';
import { UNISWAP_FACTORY_ADDRESS, DEFAULT_FEE_TIER, POOL_BYTE_CODE_HASH, REAL_BASE } from './utils/realConstants';
import { BigNumber, utils } from 'ethers';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
import { smock } from '@defi-wonderland/smock';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { hexlify, hexZeroPad, randomBytes } from 'ethers/lib/utils';
import { Q96 } from './utils/fixed-point';
const realToken = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2';

describe('VPoolFactory', () => {
  let oracle: string;
  let vBase: VBase;
  let vPoolFactory: VPoolFactory;
  let vPoolWrapperDeployer: VPoolWrapperDeployer;
  let UtilsTestContract: UtilsTest;
  let vTokenByteCode: string;
  let vPoolWrapperByteCode: string;
  let signers: SignerWithAddress[];
  before(async () => {
    await activateMainnetFork();
    const rBase = await smock.fake<ERC20>('ERC20');
    rBase.decimals.returns(18);
    const realToken = await smock.fake<ERC20>('ERC20');
    realToken.decimals.returns(10);
    vBase = await (await hre.ethers.getContractFactory('VBase')).deploy(realToken.address);
    oracle = (await (await hre.ethers.getContractFactory('OracleMock')).deploy()).address;

    signers = await hre.ethers.getSigners();
    const futureVPoolFactoryAddress = await getCreateAddressFor(signers[0], 3);
    const futureInsurnaceFundAddress = await getCreateAddressFor(signers[0], 4);

    vPoolWrapperDeployer = await (
      await hre.ethers.getContractFactory('VPoolWrapperDeployer')
    ).deploy(futureVPoolFactoryAddress);

    const accountLib = await (await hre.ethers.getContractFactory('Account')).deploy();
    const clearingHouse = await (
      await hre.ethers.getContractFactory('ClearingHouse', {
        libraries: {
          Account: accountLib.address,
        },
      })
    ).deploy(futureVPoolFactoryAddress, REAL_BASE, futureInsurnaceFundAddress);
    vPoolFactory = await (
      await hre.ethers.getContractFactory('VPoolFactory')
    ).deploy(
      vBase.address,
      clearingHouse.address,
      vPoolWrapperDeployer.address,
      UNISWAP_FACTORY_ADDRESS,
      DEFAULT_FEE_TIER,
      POOL_BYTE_CODE_HASH,
    );

    const InsuranceFund = await (
      await hre.ethers.getContractFactory('InsuranceFund')
    ).deploy(rBase.address, clearingHouse.address);

    await vBase.transferOwnership(vPoolFactory.address);

    UtilsTestContract = await (await hre.ethers.getContractFactory('UtilsTest')).deploy();

    vPoolWrapperByteCode = (await hre.ethers.getContractFactory('VPoolWrapper')).bytecode;
    vTokenByteCode = (await hre.ethers.getContractFactory('VToken')).bytecode;
  });

  after(deactivateMainnetFork.bind(null, hre));

  describe('Initilize', () => {
    it('Deployments', async () => {
      await vPoolFactory.initializePool(
        {
          setupVTokenParams: {
            vTokenName: 'vWETH',
            vTokenSymbol: 'vWETH',
            realTokenAddress: realToken,
            oracleAddress: oracle,
          },
          extendedLpFee: 500,
          protocolFee: 500,
          initialMarginRatio: 2,
          maintainanceMarginRatio: 3,
          twapDuration: 60,
          whitelisted: false,
        },
        0,
      );

      const eventFilter = vPoolFactory.filters.PoolInitlized();
      const events = await vPoolFactory.queryFilter(eventFilter, 'latest');
      const vPool = events[0].args[0];
      const vTokenAddress = events[0].args[1];
      const vPoolWrapper = events[0].args[2];

      //console.log(vTokenAddress, vPool, vPoolWrapper);
      // VToken : Create2
      let counter = 0;
      // const saltInUint160 = await UtilsTestContract.convertAddressToUint160(realToken);
      // let salt = utils.defaultAbiCoder.encode(['uint256', 'address'], [saltInUint160, realToken]);
      let bytecode = utils.solidityPack(
        ['bytes', 'bytes'],
        [
          vTokenByteCode,
          utils.defaultAbiCoder.encode(
            ['string', 'string', 'address', 'address', 'address'],
            ['vWETH', 'vWETH', realToken, oracle, vPoolFactory.address],
          ),
        ],
      );

      let vTokenComputedAddress;
      do {
        let saltHash = utils.defaultAbiCoder.encode(['uint256', 'address'], [counter, realToken]);
        vTokenComputedAddress = getCreate2Address(vPoolFactory.address, saltHash, bytecode);
        // salt = hexZeroPad(BigNumber.from(salt).add(1).toHexString(), 32);
        counter++;
      } while (BigNumber.from(vTokenComputedAddress).lt(vBase.address));
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
      let salt: string;
      if (vBase.address.toLowerCase() < vTokenAddress.toLowerCase()) {
        salt = utils.defaultAbiCoder.encode(['address', 'address', 'uint24'], [vBase.address, vTokenAddress, 500]);
      } else {
        salt = utils.defaultAbiCoder.encode(['address', 'address', 'uint24'], [vTokenAddress, vBase.address, 500]);
      }
      const vPoolCalculated = getCreate2Address2(UNISWAP_FACTORY_ADDRESS, salt, POOL_BYTE_CODE_HASH);
      expect(vPool).to.eq(vPoolCalculated);

      // VPoolWrapper : Create2
      salt = utils.defaultAbiCoder.encode(['address', 'address'], [vTokenAddress, vBase.address]);
      const vPoolWrapperCalculated = getCreate2Address(vPoolWrapperDeployer.address, salt, vPoolWrapperByteCode);
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

  describe('vToken always token0', () => {
    for (let i = 0; i < 10; i++) {
      it(`fuzz ${i + 1}`, async () => {
        const _realToken = await (await hre.ethers.getContractFactory('ERC20')).deploy('', '');
        const _oracle = await smock.fake<IOracle>('IOracle', { address: hexlify(randomBytes(20)) });
        _oracle.getTwapSqrtPriceX96.returns(Q96);
        const _extendedLpFee = Math.floor(Math.random() * 10) * 100;
        const _protocolFee = Math.floor(Math.random() * 10) * 100;
        const _initialMargin = Math.floor(Math.random() * 10) * 100;
        const _maintainanceMargin = Math.floor(Math.random() * 10) * 100;
        const _twapDuration = Math.floor(Math.random() * 10) * 100;
        const _whitelisted = Math.random() > 0.5;

        await vPoolFactory.initializePool(
          {
            setupVTokenParams: {
              vTokenName: '',
              vTokenSymbol: '',
              realTokenAddress: _realToken.address,
              oracleAddress: _oracle.address,
            },
            extendedLpFee: _extendedLpFee,
            protocolFee: _protocolFee,
            initialMarginRatio: _initialMargin,
            maintainanceMarginRatio: _maintainanceMargin,
            twapDuration: _twapDuration,
            whitelisted: _whitelisted,
          },
          0,
        );

        const events = await vPoolFactory.queryFilter(vPoolFactory.filters.PoolInitlized(), 'latest');
        const { vTokenAddress } = events[0].args;
        expect(BigNumber.from(vTokenAddress).lt(vBase.address)).to.be.true;
      });
    }
  });
});
