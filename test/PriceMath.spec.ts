import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { expect } from 'chai';
import hre from 'hardhat';
import { PriceMathTest } from '../typechain-types';

describe('Price Math', () => {
  let test: PriceMathTest;
  beforeEach(async () => {
    test = await (await hre.ethers.getContractFactory('PriceMathTest')).deploy();
  });

  describe('#toPriceX128', () => {
    const testCases: Array<{ sqrtPriceX96: BigNumberish; price0X128: BigNumberish; price1X128: BigNumberish }> = [
      {
        sqrtPriceX96: 1n << 96n,
        price0X128: 1n << 128n,
        price1X128: 1n << 128n,
      },
      {
        sqrtPriceX96: 1n << 97n,
        price0X128: 1n << 130n,
        price1X128: 1n << 126n,
      },
      {
        sqrtPriceX96: 1n << 95n,
        price0X128: 1n << 126n,
        price1X128: 1n << 130n,
      },
    ];

    for (let { sqrtPriceX96, price0X128, price1X128 } of testCases) {
      sqrtPriceX96 = BigNumber.from(sqrtPriceX96);
      price0X128 = BigNumber.from(price0X128);
      price1X128 = BigNumber.from(price1X128);

      // isToken0 is true, means no need to take reprocal
      it(`${sqrtPriceX96}(X96) == ${price0X128}(X128)`, async () => {
        expect(await test.toPriceX128(sqrtPriceX96, true)).to.eq(price0X128);
      });

      // isToken1 is false, means no need to take reprocal
      it(`1/${sqrtPriceX96}(X96) == ${price1X128}(X128)`, async () => {
        expect(await test.toPriceX128(sqrtPriceX96, false)).to.eq(price1X128);
      });
    }

    it(`0(X96) reverts`, async () => {
      expect(test.toPriceX128(0, true)).revertedWith('IllegalSqrtPrice(0)');
      expect(test.toPriceX128(0, false)).revertedWith('IllegalSqrtPrice(0)');
    });
  });
});
