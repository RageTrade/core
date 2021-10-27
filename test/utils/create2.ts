import { utils } from 'ethers';

export function getCreate2Address(deployerAddress: string, salt: string, bytecode: string): string {
  const create2Inputs = ['0xff', deployerAddress, utils.keccak256(salt), utils.keccak256(bytecode)];
  const sanitizedInputs = `0x${create2Inputs.map(i => i.slice(2)).join('')}`;
  return utils.getAddress(`0x${utils.keccak256(sanitizedInputs).slice(-40)}`);
}

export function getCreate2Address2(deployerAddress: string, salt: string, bytecodeHash: string): string {
  const create2Inputs = ['0xff', deployerAddress, utils.keccak256(salt), bytecodeHash];
  const sanitizedInputs = `0x${create2Inputs.map(i => i.slice(2)).join('')}`;
  return utils.getAddress(`0x${utils.keccak256(sanitizedInputs).slice(-40)}`);
}
