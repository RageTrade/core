import { BigNumber, BigNumberish } from '@ethersproject/bignumber';
import { expect } from 'chai';
import { randomBytes } from 'crypto';
import hre from 'hardhat';
import { SignedFullMathTest } from '../../typechain-types';

interface TestCase {
  a: BigNumberish;
  b: BigNumberish;
  denominator: BigNumberish;
  expectedResult?: BigNumberish;
}

describe('SignedFullMath', () => {
  let test: SignedFullMathTest;

  before(async () => {
    test = await (await hre.ethers.getContractFactory('SignedFullMathTest')).deploy();
  });

  describe('#mulDiv(uint256,uint256,uint256)', () => {
    const cases: Array<TestCase> = [
      {
        a: 1,
        b: 2,
        denominator: 2,
        expectedResult: 1,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: BigNumber.from(randomBytes(31)),
        b: BigNumber.from(randomBytes(31)),
        denominator: BigNumber.from(randomBytes(32)),
      },
    ];

    cases.forEach(({ a, b, denominator, expectedResult }) =>
      it(`${a.toString()} * ${b.toString()} / ${denominator.toString()}`, async () => {
        const result = await test['mulDiv(uint256,uint256,uint256)'](a, b, denominator);
        expect(result).to.eq(expectedResult ?? BigNumber.from(a).mul(b).div(denominator));
      }),
    );
  });

  describe('#mulDiv(int256,uint256,uint256)', () => {
    const cases: Array<TestCase> = [
      {
        a: 1,
        b: 2,
        denominator: 2,
        expectedResult: 1,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: BigNumber.from(randomBytes(31)),
        b: BigNumber.from(randomBytes(31)),
        denominator: BigNumber.from(randomBytes(32)),
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: -1n << 150n,
      },
    ];

    cases.forEach(({ a, b, denominator, expectedResult }) =>
      it(`${a.toString()} * ${b.toString()} / ${denominator.toString()}`, async () => {
        const result = await test['mulDiv(int256,uint256,uint256)'](a, b, denominator);
        expect(result).to.eq(expectedResult ?? BigNumber.from(a).mul(b).div(denominator));
      }),
    );
  });

  describe('#mulDivRoundingDown(int256,uint256,uint256)', () => {
    const cases: Array<TestCase> = [
      {
        a: 1,
        b: 2,
        denominator: 2,
        expectedResult: 1,
      },
      {
        a: -1,
        b: 2,
        denominator: 2,
        expectedResult: -1,
      },
      {
        a: -2,
        b: 1,
        denominator: 1,
        expectedResult: -2,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: -(1n << 150n),
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: (1n << 250n) - 1n,
        expectedResult: -((1n << 400n) / ((1n << 250n) - 1n)) - 1n,
      },
    ];

    cases.forEach(({ a, b, denominator, expectedResult }) =>
      it(`${a.toString()} * ${b.toString()} / ${denominator.toString()}`, async () => {
        const result = await test['mulDivRoundingDown(int256,uint256,uint256)'](a, b, denominator);
        expect(result).to.eq(expectedResult ?? BigNumber.from(a).mul(b).div(denominator));
      }),
    );
  });

  describe('#mulDiv(int256,int256,int256)', () => {
    const cases: Array<TestCase> = [
      {
        a: 1,
        b: 2,
        denominator: 2,
        expectedResult: 1,
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: -1n << 150n,
      },
      {
        a: 1n << 200n,
        b: -1n << 200n,
        denominator: 1n << 250n,
        expectedResult: -1n << 150n,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: -1n << 250n,
        expectedResult: -1n << 150n,
      },
      {
        a: -1n << 200n,
        b: -1n << 200n,
        denominator: 1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: -1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: 1n << 200n,
        b: -1n << 200n,
        denominator: -1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: -1n << 200n,
        b: -1n << 200n,
        denominator: -1n << 250n,
        expectedResult: -1n << 150n,
      },
      {
        a: BigNumber.from(randomBytes(30)).mul(-1),
        b: BigNumber.from(randomBytes(30)),
        denominator: BigNumber.from(randomBytes(31)),
      },
    ];

    cases.forEach(({ a, b, denominator, expectedResult }) =>
      it(`${a.toString()} * ${b.toString()} / ${denominator.toString()}`, async () => {
        const result = await test['mulDiv(int256,int256,int256)'](a, b, denominator);
        expect(result).to.eq(expectedResult ?? BigNumber.from(a).mul(b).div(denominator));
      }),
    );
  });

  describe('#mulDivRoundingDown(int256,int256,int256)', () => {
    const cases: Array<TestCase> = [
      {
        a: 1,
        b: 2,
        denominator: 2,
        expectedResult: 1,
      },
      {
        a: -1,
        b: 2,
        denominator: 2,
        expectedResult: -1,
      },
      {
        a: 1,
        b: -2,
        denominator: 2,
        expectedResult: -1,
      },
      {
        a: 1,
        b: 2,
        denominator: -2,
        expectedResult: -1,
      },
      {
        a: -2,
        b: 1,
        denominator: 1,
        expectedResult: -2,
      },
      {
        a: 2,
        b: -1,
        denominator: 1,
        expectedResult: -2,
      },
      {
        a: 2,
        b: 1,
        denominator: -1,
        expectedResult: -2,
      },
      {
        a: 2,
        b: -1,
        denominator: -1,
        expectedResult: 2,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: 1n << 150n,
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: 1n << 250n,
        expectedResult: -(1n << 150n),
      },
      {
        a: -1n << 200n,
        b: 1n << 200n,
        denominator: (1n << 250n) - 1n,
        expectedResult: -((1n << 400n) / ((1n << 250n) - 1n)) - 1n,
      },
      {
        a: 1n << 200n,
        b: -1n << 200n,
        denominator: (1n << 250n) - 1n,
        expectedResult: -((1n << 400n) / ((1n << 250n) - 1n)) - 1n,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: -((1n << 250n) - 1n),
        expectedResult: -((1n << 400n) / ((1n << 250n) - 1n)) - 1n,
      },
      {
        a: 1n << 200n,
        b: 1n << 200n,
        denominator: (1n << 250n) - 1n,
        expectedResult: (1n << 400n) / ((1n << 250n) - 1n),
      },
    ];

    cases.forEach(({ a, b, denominator, expectedResult }) =>
      it(`${a.toString()} * ${b.toString()} / ${denominator.toString()}`, async () => {
        const result = await test['mulDivRoundingDown(int256,int256,int256)'](a, b, denominator);
        expect(result).to.eq(expectedResult ?? BigNumber.from(a).mul(b).div(denominator));
      }),
    );
  });
});
