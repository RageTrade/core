// // TODO : Verify contract addresses on arb
// address constant VPOOL_FACTORY = 0xe4E6E50A2f4A6872feC414c0b3C3D1ac1a464Fe3; // TODO : Update, Deployer for VPoolWrapper, vTokens
// address constant VBASE_ADDRESS = 0xF1A16031d66de124735c920e1F2A6b28240C1A5e; // TODO : Update
// address constant UNISWAP_FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // Deployer for Uniswap Pools
// uint24 constant DEFAULT_FEE_TIER = 500;
// bytes32 constant POOL_BYTE_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
// bytes32 constant WRAPPER_BYTE_CODE_HASH = 0x6b19edb35866aacd79bca959f33a7b34690fc573018a9af2d6961e1629c4f34d; // TODO : Update
struct Constants {
    address VPOOL_FACTORY;
    address VBASE_ADDRESS;
    address UNISWAP_FACTORY_ADDRESS;
    uint24 DEFAULT_FEE_TIER;
    bytes32 POOL_BYTE_CODE_HASH;
    bytes32 WRAPPER_BYTE_CODE_HASH;
}
