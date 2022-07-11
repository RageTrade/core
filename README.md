<p>
    <a href="https://github.com/rage-trade/perpswap-contracts/actions"><img alt="test status" src="https://github.com/rage-trade/perpswap-contracts/actions/workflows/tests.yml/badge.svg"></a>
    <a href="https://solidity.readthedocs.io/en/v0.8.14/"><img alt="solidity v0.8.14" src="https://badgen.net/badge/solidity/v0.8.14/blue"></a>
</p>

# Rage Trade

This repository contains the core smart contracts for the Rage Trade Protocol.

## Bug Bounty

This repository is subject to the Rage Trade Bug Bounty program, per the terms defined [here](./BUG_BOUNTY.md).

## Scripts:

- `yarn compile`: compiles contracts
- `yarn test`: runs tests
- `yarn coverage`: runs tests and generates coverage report
- `yarn deploy --network arbtest`: for testnet deployment
- `yarn deploy --network arbmain`: for mainnet deployment

## Deployment

The live deployment files are in the [deployments](./deployments/) directory.

To deploy contracts, you can use `yarn deploy --network <network-name>`. If you're looking for details, please see [DEPLOYMENT_GUIDE](./DEPLOYMENT_GUIDE.md).

## Licensing

The primary license for Rage Trade Core is the MIT License. However, our dependencies have various licenses and hence the files that import them inherits the maximum restrictive license of it's dependencies, specified by the SPDX identifier in the file.

- For files licensed as `MIT`, please see [our license](./LICENSE).
- For files licensed as `GPL-2.0-or-later`, please see [Uniswap/v3-core's GPL](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/LICENSE_GPL).
- For files licensed as `BUSL-1.1`, please see [Uniswap/v3-core's BUSL](https://github.com/Uniswap/v3-core/blob/main/LICENSE).

You can see overview of SPDX License Identifiers used by the source code in our repository [here](./LICENSE_OVERVIEW.md).
