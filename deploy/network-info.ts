import hre from 'hardhat';

export const skip = () => true;

export interface NetworkInfo {
  CHAINLINK_ETH_USD_ORACLE?: string | undefined;
  FLAGS_INTERFACE?: string;
  SETTLEMENT_TOKEN_ADDRESS?: string;
  UNISWAP_V3_FACTORY_ADDRESS: string;
  UNISWAP_V3_DEFAULT_FEE_TIER: number;
  governanceContract?: string; // This becomes owner of Timelock contract
  timelockMinDelay?: number;
}

export const UNISWAP_V3_FACTORY_ADDRESS = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
export const UNISWAP_V3_DEFAULT_FEE_TIER = 500;

export const rinkebyInfo: NetworkInfo = {
  CHAINLINK_ETH_USD_ORACLE: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
};

export const arbitrumMainnetInfo: NetworkInfo = {
  CHAINLINK_ETH_USD_ORACLE: '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612', // https://docs.chain.link/docs/arbitrum-price-feeds/#Arbitrum%20Mainnet
  FLAGS_INTERFACE: '0x3C14e07Edd0dC67442FA96f1Ec6999c57E810a83', // https://docs.chain.link/docs/l2-sequencer-flag/#mainnet-contracts
  SETTLEMENT_TOKEN_ADDRESS: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', // USDC Arbitrum
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  governanceContract: '0xee2A909e3382cdF45a0d391202Aff3fb11956Ad1', // teamMultisig address
  timelockMinDelay: 2 * 24 * 3600, // two days
};

export const arbitrumTestnetInfo: NetworkInfo = {
  CHAINLINK_ETH_USD_ORACLE: '0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8',
  FLAGS_INTERFACE: '0x491B1dDA0A8fa069bbC1125133A975BF4e85a91b', // https://docs.chain.link/docs/l2-sequencer-flag/#rinkeby-contracts
  SETTLEMENT_TOKEN_ADDRESS: '0x33a010E74A354bd784a62cca3A4047C1A84Ceeab', // USDC Arbitrum Testnet
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  governanceContract: '0x4ec0dda0430A54b4796109913545F715B2d89F34',
  timelockMinDelay: 5 * 60, // five minutes
};

export const hardhatNetworkInfo: NetworkInfo = {
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  governanceContract: '0x4ec0dda0430A54b4796109913545F715B2d89F34',
};

export function getNetworkInfo(chainId?: number): NetworkInfo {
  switch (chainId) {
    case 4:
      return rinkebyInfo;
    case 42161:
      return arbitrumMainnetInfo;
    case 421611:
      return arbitrumTestnetInfo;
    case 31337:
      return hardhatNetworkInfo;
    default:
      throw new Error(`Chain ID ${chainId} is recognized, please add addresses to deploy/network-info.ts`);
  }
}

export const waitConfirmations = hre.network.config.chainId !== 31337 ? 2 : 0;
