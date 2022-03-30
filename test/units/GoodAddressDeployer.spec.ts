import { smock, MockContract } from '@defi-wonderland/smock';
import { expect } from 'chai';
import { BigNumber, ethers } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import hre from 'hardhat';
import { GoodAddressDeployerTest, GoodAddressDeployerTest__factory } from '../../typechain-types';

describe('GoodAddressDeployer', () => {
  let test: MockContract<GoodAddressDeployerTest>;

  let counter = 0;

  before(async () => {
    const factory = await smock.mock<GoodAddressDeployerTest__factory>('GoodAddressDeployerTest');
    test = await factory.deploy();

    // returns true if first byte of the address is zero
    test.isAddressGood.returns(([address]: [string]) => {
      counter++;
      return isAddressGood(address);
    });
  });

  afterEach(() => {
    // console.log({ counter });
    counter = 0;
  });

  describe('#deploy', () => {
    it('no constructor arg', async () => {
      const bytecode =
        '0x6080604052348015600f57600080fd5b50603f80601d6000396000f3fe6080604052600080fdfea2646970667358221220a0f87caf338929c402035c39bf40438a1355ca6280b41c5ba5a4d299b4da431e64736f6c63430008070033';

      await test.deploy(0, bytecode);

      expect(isAddressGood(await lastDeployedAddress())).to.be.true;
      expect(counter).to.be.gt(0);
    });

    it('with constructor arg', async () => {
      // constructor(uint256)
      const bytecode = ethers.utils.concat([
        '0x6080604052348015600f57600080fd5b5060405160dc38038060dc8339818101604052810190602d91906045565b506090565b600081519050603f81607c565b92915050565b60006020828403121560585760576077565b5b60006064848285016032565b91505092915050565b6000819050919050565b600080fd5b608381606d565b8114608d57600080fd5b50565b603f80609d6000396000f3fe6080604052600080fdfea26469706673582212203e8ed02a67ebf06a65e5705b2edb1d2a39d00f207411e64d33bc0aa24fa8b01f64736f6c63430008070033',
        '0x2121212121212121212121212121212121212121212121212121212121212121',
      ]);

      await test.deploy(0, bytecode);

      expect(isAddressGood(await lastDeployedAddress())).to.be.true;
      expect(counter).to.be.gt(0);
    });

    it('payable with constructor arg', async () => {
      // constructor(uint256)
      const bytecode = ethers.utils.concat([
        '0x608060405260405160d038038060d08339818101604052810190602191906039565b506084565b6000815190506033816070565b92915050565b600060208284031215604c57604b606b565b5b60006058848285016026565b91505092915050565b6000819050919050565b600080fd5b6077816061565b8114608157600080fd5b50565b603f8060916000396000f3fe6080604052600080fdfea2646970667358221220a1efd6117b608565d215653ad5187a0d0902ee031c142b1790da88c74ec94e4464736f6c63430008070033',
        '0x2121212121212121212121212121212121212121212121212121212121212121',
      ]);

      await test.signer.sendTransaction({
        to: test.address,
        value: parseEther('1'),
      });

      await test.deploy(parseEther('1'), bytecode);

      expect(isAddressGood(await lastDeployedAddress())).to.be.true;
      expect(counter).to.be.gt(0);
    });
  });

  function isAddressGood(address: string) {
    // returns true if first byte of the address is zero
    return BigNumber.from(address).lte('0x00ffffffffffffffffffffffffffffffffffffff');
  }

  async function lastDeployedAddress(): Promise<string> {
    const events = await test.queryFilter(test.filters.Address());
    const lastEvent = events[events.length - 1];
    if (lastEvent === undefined) {
      throw new Error('No Address event was emitted');
    }
    return lastEvent.args?.[0] as string;
  }
});
