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
});
