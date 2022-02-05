import { config } from 'dotenv';
import { ethers } from 'ethers';
import hre from 'hardhat';
import {
  Account__factory,
  ArbGasInfo,
  ArbGasInfo__factory,
  ArbitrumFixFeeTest__factory,
  ClearingHouse,
} from '../typechain-types';
import { ArbitrumFixFeeTest } from '../typechain-types/ArbitrumFixFeeTest';
import { activateMainnetFork } from './utils/mainnet-fork';
import { setupClearingHouse } from './utils/setup-clearinghouse';

import { wrapEthersProvider } from 'hardhat-tracer/dist/src/wrapper';
import { expect } from 'chai';

config();
const { ALCHEMY_KEY, PRIVATE_KEY } = process.env;

if (!PRIVATE_KEY) {
  throw new Error('Please add PRIVATE_KEY env that contains Arbitrum Rinkeby ETH');
}

const provider = wrapEthersProvider(
  new ethers.providers.StaticJsonRpcProvider('https://arb-rinkeby.g.alchemy.com/v2/' + ALCHEMY_KEY),
  hre.artifacts,
);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

const arbGasInfo = ArbGasInfo__factory.connect('0x000000000000000000000000000000000000006C', provider);

// TODO unskip this
// Not sure why this is failing, weird behaviour
// deployment fails with "not enough funds for gas", but there are funds.
// when RPC is changed to free rpc https://rinkeby.arbitrum.io/rpc, the deployment succeeds,
// however the queryFilter (eth_getLogs) timeouts on this free RPC.
// Skipping for now, will look after some time.
describe.skip('Arbitrum Fix Fee', () => {
  let test: ArbitrumFixFeeTest;

  before(async () => {
    test = await new ArbitrumFixFeeTest__factory(
      { 'contracts/libraries/Account.sol:Account': '0x6A1f9d165a781dB8426B009B3f91356E88A83Ab2' },
      signer,
    ).deploy();
  });

  it('getGasCostWei works', async () => {
    await test.emitGasCostWei();

    const events = await test.queryFilter(test.filters.Uint());
    expect(events[events.length - 1].args.val).to.be.gt(0);
  });

  it('claim gas works', async () => {
    const estimated = await test.estimateGas.testMethod(1);
    const [l1Fixed, calldataPerGas] = await arbGasInfo.getPricesInArbGas();

    // TODO update the test case after https://discord.com/channels/585084330037084172/859511259183448084/932558720410472488
    const gasClaim = estimated.sub(l1Fixed).sub(calldataPerGas.mul(1700));
    const tx = await test.testMethod(gasClaim, {
      gasLimit: 30_000_000, // this has to be passed more
    });
    await tx.wait();
  });
});
