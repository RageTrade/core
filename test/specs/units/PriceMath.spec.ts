import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { randomBytes } from '@ethersproject/random';
import { TickMath } from '@uniswap/v3-sdk';
import { expect } from 'chai';
import hre from 'hardhat';
import { PriceMathTest } from '../../../typechain-types';
import { priceX128ToSqrtPriceX96, sqrtPriceX96ToPriceX128 } from '../../utils/price-tick';

describe('Price Math', () => {
  let test: PriceMathTest;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('PriceMathTest')).deploy();
  });

  describe('#toPriceX128', () => {
    const testCases: Array<{ sqrtPriceX96: BigNumberish; priceX128: BigNumberish }> = [
      {
        sqrtPriceX96: 1n << 96n,
        priceX128: 1n << 128n,
      },
      {
        sqrtPriceX96: 1n << 97n,
        priceX128: 1n << 130n,
      },
      {
        sqrtPriceX96: 1n << 95n,
        priceX128: 1n << 126n,
      },
    ];

    for (let { sqrtPriceX96, priceX128 } of testCases) {
      sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
      priceX128 = BigNumber.from(priceX128);

      it(`${sqrtPriceX96}(X96) == ${priceX128}(X128)`, async () => {
        expect(await test.toPriceX128(sqrtPriceX96)).to.eq(priceX128);
      });
    }

    it(`0(X96) reverts`, async () => {
      expect(test.toPriceX128(0)).revertedWith('IllegalSqrtPrice(0)');
    });
  });

  describe('#toSqrtPriceX96', () => {
    const testCases: Array<{ sqrtPriceX96: BigNumberish; priceX128: BigNumberish }> = [
      {
        priceX128: 1n << 128n,
        sqrtPriceX96: 1n << 96n,
      },
      {
        priceX128: 1n << 130n,
        sqrtPriceX96: 1n << 97n,
      },
      {
        priceX128: 1n << 126n,
        sqrtPriceX96: 1n << 95n,
      },
      {
        priceX128: (1n << 148n) * 400n,
        sqrtPriceX96: (1n << 106n) * 20n,
      },
    ];

    for (let { priceX128, sqrtPriceX96 } of testCases) {
      priceX128 = BigNumber.from(priceX128);
      sqrtPriceX96 = BigNumber.from(sqrtPriceX96);

      it(`${priceX128}(X128) == ${sqrtPriceX96}(X96)`, async () => {
        expect(await test.toSqrtPriceX96(priceX128)).to.eq(sqrtPriceX96);
      });
    }

    it(`0(X128) reverts`, async () => {
      // all numbers 0_X96 to 4294967296_X96 square to 0_X128
      await expect(test.toSqrtPriceX96(0)).revertedWith(
        'SolutionOutOfBounds(0, 4295128739, 1461446703485210103287273052203988822378723970341)',
      );
    });

    it(`2**256-1 reverts`, async () => {
      await expect(test.toSqrtPriceX96((1n << 256n) - 1n)).revertedWith(
        'SolutionOutOfBounds(115792089237316195423570985008687907853269984665640564039457584007913129639935, 4295128739, 1461446703485210103287273052203988822378723970341)',
      );
    });

    it('fuzz perfect square', async () => {
      for (let i = 0; i++ < 100; ) {
        const sqrtPriceX96 = BigNumber.from(randomBytes(20)).mod(TickMath.MAX_SQRT_RATIO.toString());
        const priceX128 = sqrtPriceX96ToPriceX128(sqrtPriceX96);

        expect(await test.toSqrtPriceX96(priceX128)).to.eq(sqrtPriceX96);
      }
    });

    it('fuzz non perfect square', async () => {
      for (let i = 0; i++ < 100; ) {
        const priceX128 = BigNumber.from(randomBytes(20));
        const sqrtPriceX96 = priceX128ToSqrtPriceX96(priceX128);
        expect(await test.toSqrtPriceX96(priceX128)).to.eq(sqrtPriceX96);
      }
    });
  });
});
