<p>
    <a href="https://github.com/rage-trade/perpswap-contracts/actions"><img alt="test status" src="https://github.com/rage-trade/perpswap-contracts/actions/workflows/tests.yml/badge.svg"></a>
    <a href="https://solidity.readthedocs.io/en/v0.8.12/"><img alt="solidity v0.8.12" src="https://badgen.net/badge/solidity/v0.8.12/blue"></a>
</p>

# Rage Trade

This repository contains the core smart contracts for the Rage Trade Protocol.

## Bug Bounty

> Coming soon

## Scripts:

- `yarn compile`: compiles contracts
- `yarn test`: runs tests
- `yarn coverage`: runs tests and generates coverage report
- `yarn deploy:localhost`: for local deployment
- `yarn deploy:arbtest`: for testnet deployment

## Licensing

The primary license for Rage Trade Core is the MIT License, see [LICENSE](./LICENSE). However, our dependencies have various licenses and hence the files that import them inherits the maximum restrictive license of it's dependencies, specified by the SPDX identifier in the file.

> TODO: find opportunities to get rid of GPL or BUSL imports.

Following is an overview of SPDX License Identifiers used by the source code in our repository.

```
contracts
├── interfaces
│   ├── IClearingHouse.sol (GPL-2.0-or-later)
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
    ├── TransparentUpgradeableProxy.sol (MIT)
    └── constants.sol (MIT)

```
