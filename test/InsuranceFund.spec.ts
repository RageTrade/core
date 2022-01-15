import { expect } from 'chai';
import { Signer } from '@ethersproject/abstract-signer';
import hre from 'hardhat';
import { InsuranceFund, IERC20 } from '../typechain-types';
import { stealFunds, tokenAmount } from './utils/stealFunds';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
const realBase = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
const whaleForBase = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';

describe('InsuranceFund', () => {
  let InsuranceFund: InsuranceFund;
  let Base: IERC20;
  let signers: Signer[];
  let signer0Address: string;
  let signer1Address: string;
  let signer2Address: string;

  before(async () => {
    await activateMainnetFork();
    signers = await hre.ethers.getSigners();
    signer0Address = await signers[0].getAddress();
    signer1Address = await signers[1].getAddress();
    signer2Address = await signers[2].getAddress();

    const factory = await hre.ethers.getContractFactory('InsuranceFund');
    InsuranceFund = await factory.deploy();
    await InsuranceFund.__InsuranceFund_init(realBase, signer2Address, 'Rage Trade iBase', 'iBase');
    Base = await hre.ethers.getContractAt('IERC20', realBase);

    await stealFunds(realBase, 6, signer0Address, '10000', whaleForBase);
    await stealFunds(realBase, 6, signer1Address, '10000', whaleForBase);
  });

  after(deactivateMainnetFork);

  describe('Functions', () => {
    it('Is initilized Correctly', async () => {
      const _baseAdd = await InsuranceFund.rBase();
      const _clearingHouse = await InsuranceFund.clearingHouse();
      expect(_baseAdd.toLowerCase()).to.be.eq(realBase);
      expect(_clearingHouse).to.be.eq(signer2Address);
    });

    it('Deposit 1:1', async () => {
      const amount = tokenAmount('100', 6);
      await Base.approve(InsuranceFund.address, amount);
      await InsuranceFund.deposit(amount);
      const sharesMinted = await InsuranceFund.balanceOf(signer0Address);
      expect(sharesMinted).to.be.eq(amount);
    });
    // 100:100
    it('Withdraw 1:1', async () => {
      const shares = tokenAmount('50', 6);
      await InsuranceFund.withdraw(shares);
      expect(await InsuranceFund.balanceOf(signer0Address)).to.be.eq(tokenAmount('50', 6));
      expect(await Base.balanceOf(signer0Address)).to.be.eq(tokenAmount('9950', 6));
    });
    //50:50
    //100 : 50 (After reward)
    it('Deposit after : Reward, ratio 2 USDC: 1 Share', async () => {
      await stealFunds(realBase, 6, InsuranceFund.address, '50', whaleForBase);
      const amount = tokenAmount('100', 6);
      await Base.connect(signers[1]).approve(InsuranceFund.address, amount);
      await InsuranceFund.connect(signers[1]).deposit(amount);
      const sharesMinted = await InsuranceFund.connect(signers[1]).balanceOf(signer1Address);
      expect(sharesMinted).to.be.eq(tokenAmount('50', 6));
    });
    //200 : 100
    it('Withdraw after : Reward, ratio 2 USDC: 1 Share', async () => {
      const shares = tokenAmount('50', 6);
      await InsuranceFund.withdraw(shares);
      expect(await InsuranceFund.balanceOf(signer0Address)).to.be.eq(0);
      expect(await Base.balanceOf(signer0Address)).to.be.eq(tokenAmount('10050', 6));
    });
    //100 : 50
    it('Claim, ratio 1 USDC : 2 shares', async () => {
      const amount = tokenAmount('75', 6);
      await expect(InsuranceFund.claim(amount)).to.be.revertedWith('Unauthorised');
      await InsuranceFund.connect(signers[2]).claim(amount);
      expect(await Base.balanceOf(signer2Address)).to.be.eq(amount);
    });
    //25 : 50
    it('Deposit after : Claim, ratio 1 USDC: 2 Share', async () => {
      const amount = tokenAmount('100', 6);
      await Base.approve(InsuranceFund.address, amount);
      await InsuranceFund.deposit(amount);
      const sharesMinted = await InsuranceFund.balanceOf(signer0Address);
      expect(sharesMinted).to.be.eq(tokenAmount('200', 6));
    });
    //125 : 250
    it('Withdraw after : Claim, ratio 1 USDC: 2 Share', async () => {
      const shares = tokenAmount('50', 6);
      await InsuranceFund.connect(signers[1]).withdraw(shares);
      expect(await InsuranceFund.balanceOf(signer1Address)).to.be.eq(0);
      expect(await Base.balanceOf(signer1Address)).to.be.eq(tokenAmount('9925', 6));
    });
    //100 : 200
  });
});
