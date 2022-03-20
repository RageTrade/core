export const skip = () => true;

export interface NetworkInfo {
  clearingHouseContractName: string;
  settlementTokenAddress?: string;
  UNISWAP_V3_FACTORY_ADDRESS: string;
  UNISWAP_V3_DEFAULT_FEE_TIER: number;
  ETH_USD_ORACLE?: string | undefined;
}

export const UNISWAP_V3_FACTORY_ADDRESS = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
export const UNISWAP_V3_DEFAULT_FEE_TIER = 500;

export const defaultInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
};

export const arbitrumInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  settlementTokenAddress: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', // USDC Arbitrum
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
};

export const arbitrumTestnetInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  settlementTokenAddress: '0x33a010E74A354bd784a62cca3A4047C1A84Ceeab', // USDC Arbitrum Testnet
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  ETH_USD_ORACLE: '0x5f0423B1a6935dc5596e7A24d98532b67A0AeFd8',
};

export const optimisticKovanInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  ETH_USD_ORACLE: '0x7f8847242a530E809E17bF2DA5D2f9d2c4A43261',
};

export const rinkebyInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  ETH_USD_ORACLE: '0x8A753747A1Fa494EC906cE90E9f37563A8AF630e',
};

export function getNetworkInfo(chainId?: number): NetworkInfo {
  switch (chainId) {
    case 4:
      return rinkebyInfo;
    case 42161:
      return arbitrumInfo;
    case 421611:
      return arbitrumTestnetInfo;
    default:
      return defaultInfo;
  }
}
