import { smock, FakeContract } from '@defi-wonderland/smock';
import { BigNumberish } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { ethers } from 'ethers';
import hre from 'hardhat';
import { VBase, VToken } from '../../typechain-types';
import {
  priceToPriceX128,
  priceToSqrtPriceX96,
  priceX128ToPrice,
  priceX128ToSqrtPriceX96,
  sqrtPriceX96ToPrice,
  sqrtPriceX96ToPriceX128,
} from './price-tick';

describe('price-tick util', () => {
  let vBase: FakeContract<VBase>;
  let vToken: FakeContract<VToken>;

  before(async () => {
    // this makes: isToken0 as true
    vBase = await smock.fake<VBase>('VBase', {
      address: '0x0000000000000000000000000000000000000001',
    });
    vBase.decimals.returns(18);

    vToken = await smock.fake<VToken>('VToken', {
      address: '0x0000000000000000000000000000000000000000',
    });
    vToken.decimals.returns(18);
  });

  const testCases: Array<{ price: number; priceX128: BigNumberish; sqrtPriceX96: BigNumberish }> = [
    {
      price: 1,
      priceX128: 1n << 128n,
      sqrtPriceX96: 1n << 96n,
    },
    {
      price: 0.25,
      priceX128: 1n << 126n,
      sqrtPriceX96: 1n << 95n,
    },
    {
      price: 4,
      priceX128: 1n << 130n,
      sqrtPriceX96: 1n << 97n,
    },
  ];

  describe('#priceToPriceX128', () => {
    for (const { price, priceX128 } of testCases) {
      it(`${price} == ${priceX128}(X128)`, async () => {
        expect(await priceToPriceX128(price, vBase, vToken)).to.eq(priceX128);
        expect(await priceX128ToPrice(priceX128, vBase, vToken)).to.eq(price);
      });
    }
  });

  describe('#priceX128ToSqrtPriceX96', () => {
    for (const { priceX128, sqrtPriceX96 } of testCases) {
      it(`sqrt(${priceX128}(X128)) == ${sqrtPriceX96}(X96)`, async () => {
        expect(priceX128ToSqrtPriceX96(priceX128)).to.eq(sqrtPriceX96);
        expect(sqrtPriceX96ToPriceX128(sqrtPriceX96)).to.eq(priceX128);
      });
    }
  });

  describe('#priceToSqrtPriceX96', () => {
    for (const { price, sqrtPriceX96 } of testCases) {
      it(`sqrt(${price}) == ${sqrtPriceX96}(X96)`, async () => {
        expect(await priceToSqrtPriceX96(price, vBase, vToken)).to.eq(sqrtPriceX96);
        expect(await sqrtPriceX96ToPrice(sqrtPriceX96, vBase, vToken)).to.eq(price);
      });
    }
  });
});
