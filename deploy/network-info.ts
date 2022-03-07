export const skip = () => true;

export interface NetworkInfo {
  clearingHouseContractName: string;
  rBaseAddress?: string;
  UNISWAP_V3_FACTORY_ADDRESS: string;
  UNISWAP_V3_DEFAULT_FEE_TIER: number;
  UNISWAP_V3_POOL_BYTE_CODE_HASH: string;
}

export const UNISWAP_V3_FACTORY_ADDRESS = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
export const UNISWAP_V3_DEFAULT_FEE_TIER = 500;
export const UNISWAP_V3_POOL_BYTE_CODE_HASH = '0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54';

export const defaultInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouse',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
};

export const arbitrumInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouseArbitrum',
  rBaseAddress: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8', // USDC Arbitrum
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
};

export const arbitrumTestnetInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouseArbitrum',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
};

export const rinkebyInfo: NetworkInfo = {
  clearingHouseContractName: 'ClearingHouseEthereum',
  UNISWAP_V3_FACTORY_ADDRESS,
  UNISWAP_V3_DEFAULT_FEE_TIER,
  UNISWAP_V3_POOL_BYTE_CODE_HASH,
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
