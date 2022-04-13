# Deployment Guide

## Setup contracts

All the Uniswap V3 contracts on various chains exist at identical address, hence we have defined these addresses as immutable constants.

1. Ensure that UniswapV3Factory address mentioned in [constants.sol](./contracts/utils/constants.sol) is valid on the chain the deployment is being made.
2. Deploy all the logic contracts: Account library, ClearingHouse, InsuranceFund, VPoolWrapper.
3. Now deploy the RageTradeFactory contract. It will ask for the addresses of logic contracts deployed previously and USDC token address (settlement token / default collateral). Following things are performed by RageTradeFactory constructor.
   1. Deploys ProxyAdmin (Transparent Proxy).
   2. Deploys VQuote token at an address that starts from "f".
   3. Deploys proxy for InsuranceFund that points to InsuranceFund logic.
   4. Creates a settlement token oracle.
   5. Deploys proxy for ClearingHouse that points to ClearingHouse logic.
   6. Transfer ownership to deployer and initializes InsuranceFund.

## Initialize Pool

Post deployment, a new pool can be initialized using initializePool function on RageTradeFactory.

1.  Deploys vToken at an address such that it will be token0 in UniswapV3Pool.
2.  Creates UniswapV3Pool with vToken as token0 and vQuote as token1 and fee as 500 (defined in [constants.sol](./contracts/utils/constants.sol)).
3.  Initializes UniswapV3Pool.
4.  Deploys proxy for VPoolWrapper that points to VPoolWrapper logic.
5.  Does necessary authorizations and registrations.

After pool is initialized, it is not usable (swaps won't work) unless liquidity is added to it.

1.  Create an account on ClearingHouse.
2.  Add margin to it (deposit settlement token or any supported collateral).
3.  Use the margin to add liquidity using `updateRangeOrder`.
