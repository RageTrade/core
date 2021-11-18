const hre = require('hardhat');
import { BigNumber } from 'ethers';

const stealFunds = async (
  tokenAddress: string,
  tokenDecimals: number,
  receiverAddress: string,
  amount: string,
  whaleAddress: string,
) => {
  await hre.network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [whaleAddress],
  });
  const signer = await hre.ethers.getSigner(whaleAddress);
  await hre.network.provider.send('hardhat_setBalance', [signer.address, '0x1000000000000000000']);
  const token = await hre.ethers.getContractAt('IERC20', tokenAddress, signer);
  await token.transfer(receiverAddress, tokenAmount(amount, tokenDecimals));
};

const tokenAmount = (value: string, decimals: number) =>
  BigNumber.from(value).mul(BigNumber.from(10).pow(BigNumber.from(decimals)));

export { stealFunds, tokenAmount };
