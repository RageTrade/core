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

describe('DepositTokenSet Library', () => {
  let test: DepositTokenSetTest;

  let vTokenAddress: string;
  let vTokenAddress1: string;

  let vBaseAddress: string;
  let ownerAddress: string;
  let testContractAddress: string;

  let oracle: OracleMock;
  let oracle1: OracleMock;

  let realToken: RealTokenMock;
  let realToken1: RealTokenMock;

  let rToken: FakeContract<ERC20>;
  let rTokenOracle: OracleMock;
  let rToken1: FakeContract<ERC20>;
  let rToken1Oracle: OracleMock;
  // let constants: ConstantsStruct;

  let signers: SignerWithAddress[];

  before(async () => {
    await activateMainnetFork();

    rToken = await smock.fake<ERC20>('ERC20');
    rToken.decimals.returns(18);

    rTokenOracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    rToken1 = await smock.fake<ERC20>('ERC20');
    rToken1.decimals.returns(18);

    rToken1Oracle = await (await hre.ethers.getContractFactory('OracleMock')).deploy();

    signers = await hre.ethers.getSigners();

    const factory = await hre.ethers.getContractFactory('DepositTokenSetTest');
    test = await factory.deploy();

    signers = await hre.ethers.getSigners();
    const tester = signers[0];
    ownerAddress = await tester.getAddress();
    testContractAddress = test.address;
  });

  describe('#Single Token', () => {
    before(async () => {
      test.init(rToken.address, rTokenOracle.address, 300);
    });
    it('Add Margin', async () => {
      test.increaseBalance(rToken.address, 100);
      const balance = await test.getBalance(rToken.address);
      expect(balance).to.eq(100);
    });
    it('Remove Margin', async () => {
      test.decreaseBalance(rToken.address, 50);
      const balance = await test.getBalance(rToken.address);
      expect(balance).to.eq(50);
    });
    it('Deposit Market Value', async () => {
      // await oracle.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));
      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(50);
    });
  });

  describe('#Multiple Tokens', () => {
    before(async () => {
      test.init(rToken1.address, rToken1Oracle.address, 300);
      test.cleanDeposits();
    });
    it('Add Margin', async () => {
      test.increaseBalance(rToken.address, 50);
      let balance = await test.getBalance(rToken.address);
      expect(balance).to.eq(50);

      test.increaseBalance(rToken1.address, 100);
      balance = await test.getBalance(rToken1.address);
      expect(balance).to.eq(100);
    });
    it('Deposit Market Value (Price1)', async () => {
      await rToken1Oracle.setSqrtPrice(BigNumber.from(20).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(40050);
    });
    it('Deposit Market Value (Price2)', async () => {
      await rToken1Oracle.setSqrtPrice(BigNumber.from(10).mul(BigNumber.from(2).pow(96)));

      const marketValue = await test.getAllDepositAccountMarketValue();
      expect(marketValue).to.eq(10050);
    });
  });
});
