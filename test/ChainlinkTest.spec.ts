import { expect } from 'chai';
import hre, { ethers } from 'hardhat';

import { AggregatorMock, ChainlinkOracle } from '../typechain-types';
import { Q128, toQ128, fromQ128 } from './utils/fixed-point';

const latestBlockTimestamp = async () => {
    let blockNumber = await ethers.provider.getBlockNumber()
    let block = await ethers.provider.getBlock(blockNumber);
    return block.timestamp;
}

const getRounds = (timestamp: number) => {
    return {
        roundId: [1,2,3,4,5],
        answer: ['100000000', '200000000', '300000000', '400000000', '500000000'],
        startedAt: [timestamp-50, timestamp-40, timestamp-30, timestamp-20, timestamp-10],
        updatedAt: [timestamp-50, timestamp-40, timestamp-30, timestamp-20, timestamp-10],
        answeredInRound: [1, 2, 3, 4, 5]
    }
}

describe('ChainlinkOracle', () => {
    let aggregator: AggregatorMock;
    let oracle: ChainlinkOracle;
    let timestamp: number;
    let rounds: {
        roundId: Array<number>,
        answer: Array<string>,
        startedAt: Array<number>,
        updatedAt: Array<number>,
        answeredInRound: Array<number>
    };

    beforeEach(async () => {
        aggregator = await (await ethers.getContractFactory('AggregatorMock')).deploy();
        oracle = await (await ethers.getContractFactory('ChainlinkOracle')).deploy(aggregator.address);
        rounds = getRounds( await latestBlockTimestamp() )
    });

    describe('#twap price', () => {
        it('not enough round data', async () => {
            await aggregator.setHistory(
                rounds.roundId,
                rounds.answer,
                rounds.startedAt,
                rounds.updatedAt,
                rounds.answeredInRound
            );

            let twapPrice = await oracle.getTwapPriceX128(1);
            expect(twapPrice).to.eq(toQ128(5));
        });

        it('normal twap', async () => {
            await aggregator.setHistory(
                rounds.roundId,
                rounds.answer,
                rounds.startedAt,
                rounds.updatedAt,
                rounds.answeredInRound
            );

            let twapPrice = await oracle.getTwapPriceX128(10);
            expect(twapPrice).to.eq( toQ128(5) )
        });

        it('twap 20', async () => {
            await aggregator.setHistory(
                rounds.roundId,
                rounds.answer,
                rounds.startedAt,
                rounds.updatedAt,
                rounds.answeredInRound
            );

            let twapPrice = await oracle.getTwapPriceX128(20);
            expect( fromQ128(twapPrice) ).to.eq( 4.55 )
        });

        it('missing round', async () => {
            Object.values(rounds).map(arr => arr.splice(4, 1));
            await aggregator.setHistory(
                rounds.roundId,
                rounds.answer,
                rounds.startedAt,
                rounds.updatedAt,
                rounds.answeredInRound
            );

            let twapPrice = await oracle.getTwapPriceX128(28);
            expect(twapPrice).to.eq( toQ128(3.75) )
        })

    })
})