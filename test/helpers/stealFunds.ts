const hre = require('hardhat');
import { BigNumber, BigNumberish } from '@ethersproject/bignumber';

const stealFunds = async (
  tokenAddr: string,
  decimals: number,
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
  const tokenContract = await hre.ethers.getContractAt('IERC20', tokenAddr, signer);
  await tokenContract.transfer(receiverAddress, parseTokenAmount(amount, decimals));
};

const parseTokenAmount = (value: BigNumberish, decimals: number) =>
  BigNumber.from(value).mul(BigNumber.from(10).pow(BigNumber.from(decimals)));

export { stealFunds, parseTokenAmount };
