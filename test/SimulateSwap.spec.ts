import { BigNumber, ethers } from 'ethers';
import hre from 'hardhat';
import { activateMainnetFork, deactivateMainnetFork } from './utils/mainnet-fork';
import {
  IERC20,
  IERC20__factory,
  IUniswapV3Pool,
  IUniswapV3Pool__factory,
  SimulateSwapTest,
  SimulateSwapTest__factory,
} from '../typechain';
import { impersonateAccount, stopImpersonatingAccount } from './utils/impersonate-account';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { formatUnits, parseEther, parseUnits } from '@ethersproject/units';

const UNISWAP_REAL_POOL = '0x8ad599c3a0ff1de082011efddc58f1908eb6e6d8';
const ACCOUNT = '0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0';
const SWAP = {
  USDC_FOR_WETH: true,
  WETH_FOR_USDC: false,
};

describe('SimulateSwap', () => {
  let signer: SignerWithAddress;
  let v3Pool: IUniswapV3Pool;
  let test: SimulateSwapTest;

  before(async () => {
    await activateMainnetFork(hre, 13555700);
    signer = await impersonateAccount(ACCOUNT);
    v3Pool = IUniswapV3Pool__factory.connect(UNISWAP_REAL_POOL, signer);
    test = await new SimulateSwapTest__factory(signer).deploy(UNISWAP_REAL_POOL);
    await IERC20__factory.connect(await v3Pool.token0(), signer).approve(test.address, ethers.constants.MaxInt256);
    await IERC20__factory.connect(await v3Pool.token1(), signer).approve(test.address, ethers.constants.MaxInt256);
  });

  after(async () => {
    await stopImpersonatingAccount(ACCOUNT);
    await deactivateMainnetFork(hre);
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
});

function parseUsdc(str: string): BigNumber {
  return parseUnits(str.replaceAll(',', ''), 6);
}
