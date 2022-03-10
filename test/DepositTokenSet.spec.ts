import { expect } from 'chai';
import hre from 'hardhat';

import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import { getCreateAddressFor } from './utils/create-addresses';
import {
  DepositTokenSetTest,
  RageTradeFactory,
  ClearingHouse,
  OracleMock,
  RealTokenMock,
  ERC20,
} from '../typechain-types';

import { utils } from 'ethers';
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
// import { ConstantsStruct } from '../typechain-types/ClearingHouse';
import {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
  REAL_BASE,
} from './utils/realConstants';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { FakeContract, smock } from '@defi-wonderland/smock';

describe('CTokenDepositSet Library', () => {
  let test: DepositTokenSetTest;

  let vTokenAddress: string;
  let vTokenAddress1: string;

  let vQuoteAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;

  let cBase: FakeContract<ERC20>;

  let cToken: FakeContract<ERC20>;
  let cTokenOracle: OracleMock;
  let cToken1: FakeContract<ERC20>;
  let cToken1Oracle: OracleMock;
  // let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

  before(async () => {
    await activateMainnetFork();

    cBase = await smock.fake<ERC20>('ERC20');
    cBase.decimals.returns(6);

    cToken = await smock.fake<ERC20>('ERC20');
    cToken.decimals.returns(18);

    cTokenOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    cToken1 = await smock.fake<ERC20>('ERC20');
    cToken1.decimals.returns(18);

    cToken1Oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    signers = await hre.ethers.getSigners();

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy(cBase.address);

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;
  });

  describe('#Single Token', () => {
    before(async () => {
      test.init(cToken.address, cTokenOracle.address, 300);
    });
    it('Add Margin', async () => {
      test.increaseBalance(cToken.address, 100);
      const balance = await test.getBalance(cToken.address);
      expect(balance).to.eq(100);
    });
    it('Remove Margin', async () => {
      test.decreaseBalance(cToken.address, 50);
      const balance = await test.getBalance(cToken.address);
      expect(balance).to.eq(50);
    });
    it('Deposit Market Value', async () => {
      // await oracle.setSqrtPriceX96(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));
      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(50);
    });
  });

  describe('#Multiple Tokens', () => {
    before(async () => {
      test.init(cToken1.address, cToken1Oracle.address, 300);
      test.cleanDeposits();
    });
    it('Add Margin', async () => {
      test.increaseBalance(cToken.address, 50);
      let balance = await test.getBalance(cToken.address);
      expect(balance).to.eq(50);

      test.increaseBalance(cToken1.address, 100);
      balance = await test.getBalance(cToken1.address);
      expect(balance).to.eq(100);
    });
    it('Deposit Market Value (Price1)', async () => {
      await cToken1Oracle.setPriceX128(BigNumber.from(400).mul(BigNumber.from(2).pow(128)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(40050);
    });
    it('Deposit Market Value (Price2)', async () => {
      await cToken1Oracle.setPriceX128(BigNumber.from(100).mul(BigNumber.from(2).pow(128)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(10050);
    });
  });
});
