<p>
    <a href="https://github.com/rage-trade/perpswap-contracts/actions"><img alt="test status" src="https://github.com/rage-trade/perpswap-contracts/actions/workflows/tests.yml/badge.svg"></a>
    <a href="https://solidity.readthedocs.io/en/v0.8.13/"><img alt="solidity v0.8.13" src="https://badgen.net/badge/solidity/v0.8.13/blue"></a>
</p>

# Rage Trade

This repository contains the core smart contracts for the Rage Trade Protocol.

## Bug Bounty

> Coming soon

## Scripts:

- `yarn compile`: compiles contracts
- `yarn test`: runs tests
- `yarn coverage`: runs tests and generates coverage report
- `yarn deploy --network localhost`: for local deployment
- `yarn deploy --network arbtest`: for testnet deployment
- `yarn deploy --network arbmain`: for mainnet deployment

## Deployment Guide

To deploy contracts `yarn deploy --network <network-name>` should do the job. But anyway this section elaborates on how it works.

1. All the Uniswap V3 contracts on various chains exist at identical address, hence we have defined these addresses as immutable constants. Ensure that UniswapV3Factory address mentioned in [constants.sol](./contracts/utils/constants.sol) is valid on the chain the deployment is being made.
2. Deploy all the logic contracts: Account library, ClearingHouse, InsuranceFund, VPoolWrapper.
3. Now deploy the RageTradeFactory contract. It will ask for the addresses of logic contracts deployed previously and USDC token address (settlement token / default collateral). Following things are performed by RageTradeFactory constructor.
   1. Deploys ProxyAdmin (Transparent Proxy).
   2. Deploys VQuote token at an address that starts from "f".
   3. Deploys proxy for InsuranceFund that points to InsuranceFund logic.
   4. Creates a settlement token oracle.
   5. Deploys proxy for ClearingHouse that points to ClearingHouse logic.
   6. Transfer ownership to deployer and initializes InsuranceFund.
4. Post deployment, a new pool can be initialized using initializePool function on RageTradeFactory.
   1. Deploys vToken at an address such that it will be token0 in UniswapV3Pool.
   2. Creates UniswapV3Pool with vToken as token0 and vQuote as token1 and fee as 500 (defined in [constants.sol](./contracts/utils/constants.sol)).
   3. Initializes UniswapV3Pool.
   4. Deploys proxy for VPoolWrapper that points to VPoolWrapper logic.
   5. Does necessary authorizations and registrations.
5. After pool is initialized, it is not usable (swaps won't work) unless liquidity is added to it.
   1. Create an account on ClearingHouse.
   2. Add margin to it (deposit settlement token or any supported collateral).
   3. Use the margin to add liquidity using `updateRangeOrder`.

## Licensing

The primary license for Rage Trade Core is the MIT License. However, our dependencies have various licenses and hence the files that import them inherits the maximum restrictive license of it's dependencies, specified by the SPDX identifier in the file.

- For files licensed as `MIT`, please see [our license](./LICENSE).
- For files licensed as `GPL-2.0-or-later`, please see [Uniswap/v3-core's GPL](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/LICENSE_GPL).
- For files licensed as `BUSL-1.1`, please see [Uniswap/v3-core's BUSL](https://github.com/Uniswap/v3-core/blob/main/LICENSE).

Following is an overview of SPDX License Identifiers used by the source code in our repository.

```
contracts
├── extsloads
│   └── ClearingHouseExtsload.sol (MIT)
├── interfaces
│   ├── IClearingHouse.sol (GPL-2.0-or-later)
│   ├── IExtsload.sol (MIT)
│   ├── IGovernable.sol (MIT)
│   ├── IInsuranceFund.sol (GPL-2.0-or-later)
│   ├── IOracle.sol (MIT)
│   ├── IVPoolWrapper.sol (GPL-2.0-or-later)
│   ├── IVQuote.sol (MIT)
│   ├── IVToken.sol (MIT)
│   └── clearinghouse
│       ├── IClearingHouseActions.sol (GPL-2.0-or-later)
│       ├── IClearingHouseCustomErrors.sol (GPL-2.0-or-later)
│       ├── IClearingHouseEnums.sol (MIT)
│       ├── IClearingHouseEvents.sol (GPL-2.0-or-later)
│       ├── IClearingHouseOwnerActions.sol (GPL-2.0-or-later)
│       ├── IClearingHouseStructures.sol (GPL-2.0-or-later)
│       ├── IClearingHouseSystemActions.sol (GPL-2.0-or-later)
│       └── IClearingHouseView.sol (GPL-2.0-or-later)
├── libraries
│   ├── Account.sol (BUSL-1.1)
│   ├── AddressHelper.sol (MIT)
│   ├── Bisection.sol (MIT)
│   ├── Bytes32.sol (MIT)
│   ├── CollateralDeposit.sol (GPL-2.0-or-later)
│   ├── FundingPayment.sol (GPL-2.0-or-later)
│   ├── GoodAddressDeployer.sol (MIT)
│   ├── LiquidityPosition.sol (BUSL-1.1)
│   ├── LiquidityPositionSet.sol (BUSL-1.1)
│   ├── PriceMath.sol (GPL-2.0-or-later)
│   ├── Protocol.sol (GPL-2.0-or-later)
│   ├── SafeCast.sol (MIT)
│   ├── SignedFullMath.sol (GPL-2.0-or-later)
│   ├── SignedMath.sol (MIT)
│   ├── SimulateSwap.sol (BUSL-1.1)
│   ├── SwapMath.sol (GPL-2.0-or-later)
│   ├── TickBitmapExtended.sol (BUSL-1.1)
│   ├── TickExtended.sol (GPL-2.0-or-later)
│   ├── Uint32L8Array.sol (MIT)
│   ├── Uint48.sol (MIT)
│   ├── Uint48L5Array.sol (MIT)
│   ├── UniswapV3PoolHelper.sol (GPL-2.0-or-later)
│   ├── VTokenPosition.sol (BUSL-1.1)
│   └── VTokenPositionSet.sol (BUSL-1.1)
├── oracles
│   ├── ChainlinkOracle.sol (GPL-2.0-or-later)
│   └── SettlementTokenOracle.sol (GPL-2.0-or-later)
├── protocol
│   ├── RageTradeFactory.sol (GPL-2.0-or-later)
│   ├── clearinghouse
│   │   ├── ClearingHouse.sol (BUSL-1.1)
│   │   ├── ClearingHouseDeployer.sol (GPL-2.0-or-later)
│   │   ├── ClearingHouseStorage.sol (BUSL-1.1)
│   │   └── ClearingHouseView.sol (BUSL-1.1)
│   ├── insurancefund
│   │   ├── InsuranceFund.sol (GPL-2.0-or-later)
│   │   └── InsuranceFundDeployer.sol (GPL-2.0-or-later)
│   ├── tokens
│   │   ├── VQuote.sol (GPL-2.0-or-later)
│   │   ├── VQuoteDeployer.sol (GPL-2.0-or-later)
│   │   ├── VToken.sol (MIT)
│   │   └── VTokenDeployer.sol (MIT)
│   └── wrapper
│       ├── VPoolWrapper.sol (BUSL-1.1)
│       └── VPoolWrapperDeployer.sol (GPL-2.0-or-later)
├── test (UNLICENSED)
└── utils
    ├── Extsload.sol (MIT)
    ├── Governable.sol (MIT)
    ├── Multicall.sol (GPL-2.0-or-later)
    ├── ProxyAdmin.sol (MIT)
    ├── ProxyAdminDeployer.sol (MIT)
    ├── SwapSimulator.sol (BUSL-1.1)
    ├── TimelockControllerWithMinDelayOverride.sol (MIT)
    ├── TransparentUpgradeableProxy.sol (MIT)
    └── constants.sol (MIT)
```
