import { expect } from 'chai';
import { randomBytes } from 'crypto';
import { ethers } from 'ethers';
import { concat, hexlify } from 'ethers/lib/utils';
import hre, { waffle } from 'hardhat';
import { TimelockControllerWithMinDelayOverrideTest } from '../../typechain-types';
const { AddressZero, HashZero } = ethers.constants;

describe('TimelockControllerWithMinDelayOverride', () => {
  const MIN_DELAY_DEFAULT = 100;

  let timelock: TimelockControllerWithMinDelayOverrideTest;
  const fixture = async () => {
    const [admin] = await hre.ethers.getSigners();
    return await (
      await hre.ethers.getContractFactory('TimelockControllerWithMinDelayOverrideTest')
    ).deploy(MIN_DELAY_DEFAULT, [admin.address], [admin.address]);
  };

  beforeEach(async () => {
    timelock = await waffle.loadFixture(fixture);
  });

  describe('#getSelector', () => {
    const testCases: Array<{ input: string; output: string }> = [
      {
        input: '0x0000000000000000000000000000000000000000000000000000000000000001',
        output: '0x00000000',
      },
      {
        input:
          '0x095ea7b300000000000000000000000068b3465833fb72a70ecdf485e0e4c7bd8665fc45ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        output: '0x095ea7b3',
      },
      {
        input:
          '0xa9059cbb0000000000000000000000004c4add20570dc96ccc87b02bf8cf4ef5e02b6f740000000000000000000000000000000000000000000000000000000014dc9380',
        output: '0xa9059cbb',
      },
      {
        input: '0x12345678',
        output: '0x12345678',
      },
      {
        input: '0x1234567890',
        output: '0x12345678',
      },
    ];

    for (const [, { input, output }] of testCases.entries()) {
      it(`getSelector(${input}) == ${output}`, async () => {
        expect(await getSelector(input)).to.equal(output);
      });
    }

    it(`getSelector(0x) reverts`, async () => {
      await expect(getSelector('0x')).to.be.reverted;
    });

    it(`getSelector(0x12) reverts`, async () => {
      await expect(getSelector('0x12')).to.be.reverted;
    });

    it(`getSelector(0x0000) reverts`, async () => {
      await expect(getSelector('0x0000')).to.be.reverted;
    });

    it(`getSelector(0x000000) reverts`, async () => {
      await expect(getSelector('0x000000')).to.be.reverted;
    });

    it('fuzz', async () => {
      for (const _ of Array(100)) {
        const length = 4 + Math.floor(Math.random() * 200);
        const data = hexlify(randomBytes(length));
        expect(await getSelector(data)).to.equal(data.slice(0, 10));
      }
    });
  });

  describe('#getKey', () => {
    it('getKey(0x2222222222222222222222222222222222222222, 0x11111111) == 0x0000000000000000111111112222222222222222222222222222222222222222', async () => {
      expect(await timelock.getKey('0x2222222222222222222222222222222222222222', '0x11111111')).to.equal(
        '0x1111111100000000000000002222222222222222222222222222222222222222',
      );
    });

    it('fuzz', async () => {
      for (const _ of Array(100)) {
        const address = hexlify(randomBytes(20));
        const selector = hexlify(randomBytes(4));
        const resultExpected = hexlify(concat([selector, '0x0000000000000000', address]));
        expect(await timelock.getKey(address, selector)).to.equal(resultExpected);
      }
    });
  });

  describe('#minDelayOverride', () => {
    it('can not just set minDelayOverride immediately from admin wallet', async () => {
      // requires to be set using timelock
      await expect(timelock.setMinDelayOverride(AddressZero, '0x11111111', 50)).to.be.reverted;
    });

    it('set works', async () => {
      const DELAY_OVERRIDE = MIN_DELAY_DEFAULT + 50;

      const tx = await timelock.populateTransaction.setMinDelayOverride(AddressZero, '0x11111111', DELAY_OVERRIDE);
      if (tx.data === undefined) throw new Error('data is undefined');

      // reverts on using a delay less than the current minDelay
      await expect(
        timelock.schedule(timelock.address, 0, tx.data, HashZero, HashZero, MIN_DELAY_DEFAULT - 1),
      ).to.be.revertedWith('TimelockController: insufficient delay');

      // works with the current minDelay
      await timelock.schedule(timelock.address, 0, tx.data, HashZero, HashZero, MIN_DELAY_DEFAULT);

      // increase time
      await hre.ethers.provider.send('evm_increaseTime', [MIN_DELAY_DEFAULT]);

      // execute the min delay update
      const { target, value, data, predecessor } = await getLastId();
      await timelock.execute(target, value, data, predecessor, HashZero);

      // check that the min delay was updated
      expect(await timelock.getMinDelayOverride(AddressZero, '0x11111111')).to.equal(DELAY_OVERRIDE);

      // check that the global min delay was not updated
      expect(await timelock.getMinDelay()).to.equal(MIN_DELAY_DEFAULT);

      // now try to schedule a transaction with the MIN_DELAY_DEFAULT, should revert, since DELAY_OVERRIDE > MIN_DELAY_DEFAULT
      await expect(
        timelock.schedule(AddressZero, 0, '0x11111111', HashZero, HashZero, MIN_DELAY_DEFAULT),
      ).to.be.revertedWith('TimelockController: insufficient delay');

      // works with override
      await timelock.schedule(AddressZero, 0, '0x11111111', HashZero, HashZero, DELAY_OVERRIDE);

      // check that the global min delay was not updated
      expect(await timelock.getMinDelay()).to.equal(MIN_DELAY_DEFAULT);
    });

    it('unset works', async () => {
      // setting override
      const DELAY_OVERRIDE = MIN_DELAY_DEFAULT + 50;
      const tx = await timelock.populateTransaction.setMinDelayOverride(AddressZero, '0x11111111', DELAY_OVERRIDE);
      if (tx.data === undefined) throw new Error('data is undefined');
      await timelock.schedule(timelock.address, 0, tx.data, HashZero, HashZero, MIN_DELAY_DEFAULT);
      await hre.ethers.provider.send('evm_increaseTime', [MIN_DELAY_DEFAULT]);
      const { target, value, data, predecessor } = await getLastId();
      await timelock.execute(target, value, data, predecessor, HashZero);

      expect(await timelock.getMinDelayOverride(AddressZero, '0x11111111')).to.equal(DELAY_OVERRIDE);
      expect(await timelock.getMinDelay()).to.equal(MIN_DELAY_DEFAULT);

      // unsetting override
      const tx2 = await timelock.populateTransaction.unsetMinDelayOverride(AddressZero, '0x11111111');
      if (tx2.data === undefined) throw new Error('data is undefined');
      await timelock.schedule(timelock.address, 0, tx2.data, HashZero, HashZero, MIN_DELAY_DEFAULT);
      await hre.ethers.provider.send('evm_increaseTime', [MIN_DELAY_DEFAULT]);
      const { target: target2, value: value2, data: data2, predecessor: predecessor2 } = await getLastId();
      await timelock.execute(target2, value2, data2, predecessor2, HashZero);

      await expect(timelock.getMinDelayOverride(AddressZero, '0x11111111')).to.be.revertedWith(
        'minDelayOverride not set',
      );
      expect(await timelock.getMinDelay()).to.equal(MIN_DELAY_DEFAULT);
    });
  });

  async function getSelector(input: string) {
    return await timelock.getSelector(AddressZero, 0, input, HashZero, HashZero, 0);
  }

  async function getLastId() {
    const events = await timelock.queryFilter(timelock.filters.CallScheduled());
    return events[events.length - 1].args;
  }
});
