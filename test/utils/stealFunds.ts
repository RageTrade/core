const hre = require('hardhat');
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

const stealFunds = async (
  tokenAddress: string,
  tokenDecimals: number,
  receiverAddress: string,
  amount: BigNumberish,
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

const tokenAmount = (value: BigNumberish, decimals: number) =>
  BigNumber.from(value).mul(BigNumber.from(10).pow(BigNumber.from(decimals)));

export { stealFunds, tokenAmount };
