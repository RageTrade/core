import hre from 'hardhat';

export async function impersonateAccount(address: string) {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });
  return await hre.ethers.getSigner(address);
}

export async function stopImpersonatingAccount(address: string) {
  await hre.network.provider.request({
    method: 'hardhat_stopImpersonatingAccount',
    params: [address],
  });
}
