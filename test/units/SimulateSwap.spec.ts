import { BigNumber, ethers } from 'ethers';
import hre from 'hardhat';
import { activateMainnetFork, deactivateMainnetFork } from '../helpers/mainnet-fork';
import { IUniswapV3Pool, OracleMock, SimulateSwapTest } from '../../typechain-types';
import { impersonateAccount, stopImpersonatingAccount } from '../helpers/impersonate-account';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { formatUnits, parseEther, parseUnits } from '@ethersproject/units';
import { Q128 } from '../helpers/fixed-point';

const UNISWAP_REAL_POOL = '0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8';
const ACCOUNT = '0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0';
const SWAP = {
  USDC_FOR_WETH: true,
  WETH_FOR_USDC: false,
};

describe('SimulateSwap', () => {
  let signer: SignerWithAddress;
  let v3Pool: IUniswapV3Pool;
  let oracle: OracleMock;
  let test: SimulateSwapTest;

  before(async () => {
    await activateMainnetFork({ blockNumber: 13555700, network: 'mainnet' });
    signer = await impersonateAccount(ACCOUNT);
    v3Pool = (await hre.ethers.getContractAt(
      '@uniswap/v3-core-0.8-support/contracts/interfaces/IUniswapV3Pool.sol:IUniswapV3Pool',
      UNISWAP_REAL_POOL,
      signer,
    )) as IUniswapV3Pool;

    test = await (await hre.ethers.getContractFactory('SimulateSwapTest', signer)).deploy(UNISWAP_REAL_POOL);

    (await hre.ethers.getContractAt('IERC20', await v3Pool.token0(), signer)).approve(
      test.address,
      ethers.constants.MaxInt256,
    );
    (await hre.ethers.getContractAt('IERC20', await v3Pool.token1(), signer)).approve(
      test.address,
      ethers.constants.MaxInt256,
    );
  });

  after(async () => {
    await stopImpersonatingAccount(ACCOUNT);
    await deactivateMainnetFork();
  });

  const testCases: Array<{
    zeroForOne: boolean;
    amountSpecified: BigNumber;
  }> = [
    {
      zeroForOne: SWAP.WETH_FOR_USDC,
      amountSpecified: parseEther('1'),
    },
    {
      zeroForOne: SWAP.WETH_FOR_USDC,
      amountSpecified: parseEther('100'),
    },
    {
      zeroForOne: SWAP.WETH_FOR_USDC,
      amountSpecified: parseEther('10000'),
    },
    {
      zeroForOne: SWAP.USDC_FOR_WETH,
      amountSpecified: parseUsdc('1'),
    },
    {
      zeroForOne: SWAP.USDC_FOR_WETH,
      amountSpecified: parseUsdc('10,000,000'),
    },
    {
      zeroForOne: SWAP.USDC_FOR_WETH,
      amountSpecified: parseUsdc('50,000,000'),
    },
  ];

  describe('#amounts', () => {
    for (const { zeroForOne, amountSpecified } of testCases) {
      it(`swap ${formatUnits(amountSpecified, zeroForOne ? 6 : 18)} ${zeroForOne ? 'USDC' : 'WETH'} for ${
        zeroForOne ? 'WETH' : 'USDC'
      }`, async () => {
        const sqrtPrice = await test.sqrtPrice();
        const [amount0_simulated, amount1_simulated] = await test.callStatic.simulateSwap1(
          zeroForOne,
          amountSpecified,
          zeroForOne ? sqrtPrice.div(2) : sqrtPrice.mul(2),
        );
        const [amount0_actual, amount1_actual] = await test.callStatic.swap(
          zeroForOne,
          amountSpecified,
          zeroForOne ? sqrtPrice.div(2) : sqrtPrice.mul(2),
        );

        expect(amount0_simulated).to.eq(amount0_actual);
        expect(amount1_simulated).to.eq(amount1_actual);
      });
    }
  });

  describe('#onSwapStep', () => {
    beforeEach(async () => {
      await test.clearSwapSteps();
    });

    for (const { zeroForOne, amountSpecified } of testCases) {
      it(`swap ${formatUnits(amountSpecified, zeroForOne ? 6 : 18)} ${zeroForOne ? 'USDC' : 'WETH'} for ${
        zeroForOne ? 'WETH' : 'USDC'
      }`, async () => {
        const fpGlobalBefore = await test.fpGlobal();

        const sqrtPrice = await test.sqrtPrice();
        const [amount0_simulated, amount1_simulated, cache, steps] = await test.callStatic.simulateSwap2(
          zeroForOne,
          amountSpecified,
          zeroForOne ? sqrtPrice.div(2) : sqrtPrice.mul(2),
        );
        await test.simulateSwap2(zeroForOne, amountSpecified, zeroForOne ? sqrtPrice.div(2) : sqrtPrice.mul(2));

        let amountSent = BigNumber.from(0);
        let amountReceived = BigNumber.from(0);
        let b = BigNumber.from(0);

        for (const { state, step } of steps) {
          amountSent = amountSent.add(step.amountIn.add(step.feeAmount));
          amountReceived = amountReceived.sub(step.amountOut);
          b = b.add((zeroForOne ? step.amountOut : step.amountIn).mul(Q128).div(state.liquidity));
        }

        expect(amountSent).to.eq(zeroForOne ? amount0_simulated : amount1_simulated);
        expect(amountReceived).to.eq(zeroForOne ? amount1_simulated : amount0_simulated);
      });
    }
  });
});

function parseUsdc(str: string): BigNumber {
  return parseUnits(str.replaceAll(',', ''), 6);
}
